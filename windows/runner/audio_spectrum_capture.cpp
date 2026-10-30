#include "audio_spectrum_capture.h"

#include <audioclient.h>
#include <ksmedia.h>
#include <mmdeviceapi.h>
#include <objbase.h>
#include <windows.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace {
constexpr size_t kSampleWindow = 2048;
constexpr double kPi = 3.14159265358979323846;
constexpr size_t kBandCount = 32;

void ReleaseCom(IUnknown* value) {
  if (value) value->Release();
}

bool IsFloatFormat(const WAVEFORMATEX* format) {
  if (format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) return true;
  if (format->wFormatTag != WAVE_FORMAT_EXTENSIBLE ||
      format->cbSize < sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX)) {
    return false;
  }
  const auto* extensible = reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format);
  return extensible->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
}

float ReadSample(const BYTE* data, size_t index, WORD bits, bool is_float) {
  if (is_float && bits == 32) {
    float sample = 0.0f;
    std::memcpy(&sample, data + index * sizeof(float), sizeof(float));
    return std::clamp(sample, -1.0f, 1.0f);
  }
  if (bits == 16) {
    int16_t sample = 0;
    std::memcpy(&sample, data + index * sizeof(sample), sizeof(sample));
    return static_cast<float>(sample) / 32768.0f;
  }
  if (bits == 24) {
    const BYTE* bytes = data + index * 3;
    int32_t sample = static_cast<int32_t>(bytes[0]) |
                     (static_cast<int32_t>(bytes[1]) << 8) |
                     (static_cast<int32_t>(bytes[2]) << 16);
    if (sample & 0x800000) sample |= ~0xFFFFFF;
    return static_cast<float>(sample) / 8388608.0f;
  }
  if (bits == 32) {
    int32_t sample = 0;
    std::memcpy(&sample, data + index * sizeof(sample), sizeof(sample));
    return static_cast<float>(sample) / 2147483648.0f;
  }
  return 0.0f;
}

bool IsDefaultMultimediaEndpoint(IMMDeviceEnumerator* enumerator,
                                 const std::wstring& active_endpoint_id) {
  IMMDevice* default_device = nullptr;
  if (FAILED(enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia,
                                                  &default_device))) {
    return false;
  }
  LPWSTR endpoint_id = nullptr;
  const HRESULT result = default_device->GetId(&endpoint_id);
  const bool is_same = SUCCEEDED(result) && endpoint_id &&
                       active_endpoint_id == endpoint_id;
  if (endpoint_id) CoTaskMemFree(endpoint_id);
  ReleaseCom(default_device);
  return is_same;
}

std::array<float, kBandCount> AnalyzeBands(
    const std::array<float, kSampleWindow>& samples, uint32_t sample_rate) {
  std::array<float, kBandCount> result{};
  std::array<double, kSampleWindow> windowed{};
  for (size_t i = 0; i < kSampleWindow; ++i) {
    const double hann = 0.5 - 0.5 * std::cos(2.0 * kPi * i /
                                            (kSampleWindow - 1));
    windowed[i] = samples[i] * hann;
  }

  const double maximum_frequency = std::min(12000.0, sample_rate * 0.45);
  const double minimum_frequency = std::min(55.0, maximum_frequency / 8.0);
  for (size_t band = 0; band < kBandCount; ++band) {
    const double fraction = static_cast<double>(band) / (kBandCount - 1);
    const double frequency = minimum_frequency *
        std::pow(maximum_frequency / minimum_frequency, fraction);
    const double omega = 2.0 * kPi * frequency / sample_rate;
    const double coefficient = 2.0 * std::cos(omega);
    double previous = 0.0;
    double previous_previous = 0.0;
    for (double sample : windowed) {
      const double current = sample + coefficient * previous -
                             previous_previous;
      previous_previous = previous;
      previous = current;
    }
    const double power = std::max(
        0.0, previous * previous + previous_previous * previous_previous -
                 coefficient * previous * previous_previous);
    const double amplitude = 2.0 * std::sqrt(power) / kSampleWindow;
    const double gated = std::clamp((amplitude - 0.0025) * 12.0, 0.0, 1.0);
    result[band] = static_cast<float>(std::sqrt(gated));
  }
  return result;
}
}  // namespace

AudioSpectrumCapture::~AudioSpectrumCapture() { Stop(); }

void AudioSpectrumCapture::Start() {
  if (running_.exchange(true)) return;
  if (capture_thread_.joinable()) capture_thread_.join();
  capture_thread_ = std::thread(&AudioSpectrumCapture::CaptureLoop, this);
}

void AudioSpectrumCapture::Stop() {
  running_.store(false);
  if (capture_thread_.joinable()) capture_thread_.join();
  std::lock_guard<std::mutex> lock(spectrum_mutex_);
  spectrum_.fill(0.0f);
}

std::vector<double> AudioSpectrumCapture::GetSpectrum() const {
  std::lock_guard<std::mutex> lock(spectrum_mutex_);
  std::vector<double> result;
  result.reserve(spectrum_.size());
  for (float value : spectrum_) result.push_back(value);
  return result;
}

void AudioSpectrumCapture::CaptureLoop() {
  const HRESULT com_result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool uninitialize_com = SUCCEEDED(com_result);
  // The default render endpoint can change while the app is running (for
  // example, when headphones are connected). WASAPI loopback clients are tied
  // to the endpoint they were created for, so rebuild the client after any
  // initialization or capture error and keep trying while Explore is open.
  while (running_.load()) {
    IMMDeviceEnumerator* enumerator = nullptr;
    IMMDevice* device = nullptr;
    IAudioClient* audio_client = nullptr;
    IAudioCaptureClient* capture_client = nullptr;
    WAVEFORMATEX* format = nullptr;
    std::wstring active_endpoint_id;

    bool initialized =
        SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                   CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                   reinterpret_cast<void**>(&enumerator))) &&
        SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia,
                                                      &device));
    if (initialized) {
      LPWSTR endpoint_id = nullptr;
      initialized = SUCCEEDED(device->GetId(&endpoint_id)) && endpoint_id;
      if (initialized) active_endpoint_id = endpoint_id;
      if (endpoint_id) CoTaskMemFree(endpoint_id);
    }
    initialized = initialized &&
        SUCCEEDED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                   reinterpret_cast<void**>(&audio_client))) &&
        SUCCEEDED(audio_client->GetMixFormat(&format)) &&
        SUCCEEDED(audio_client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                           AUDCLNT_STREAMFLAGS_LOOPBACK,
                                           500000, 0, format, nullptr)) &&
        SUCCEEDED(audio_client->GetService(__uuidof(IAudioCaptureClient),
                                           reinterpret_cast<void**>(
                                               &capture_client))) &&
        SUCCEEDED(audio_client->Start());

    bool captured = false;
    if (initialized && format && format->nSamplesPerSec > 0 &&
        format->nChannels > 0) {
      captured = true;
      const bool is_float = IsFloatFormat(format);
      std::array<float, kSampleWindow> ring{};
      size_t write_index = 0;
      size_t filled = 0;
      ULONGLONG last_endpoint_check = GetTickCount64();
      while (running_.load()) {
        // WASAPI loopback remains attached to its original endpoint after a
        // headphone/default-device switch. Detect the new multimedia endpoint
        // and recreate the client so the visualizer follows the active output.
        const ULONGLONG now = GetTickCount64();
        if (now - last_endpoint_check >= 1000) {
          last_endpoint_check = now;
          if (!IsDefaultMultimediaEndpoint(enumerator, active_endpoint_id)) {
            captured = false;
            break;
          }
        }
        UINT32 packet_frames = 0;
        if (FAILED(capture_client->GetNextPacketSize(&packet_frames))) {
          captured = false;
          break;
        }
        bool received_samples = false;
        while (packet_frames > 0 && running_.load()) {
          BYTE* buffer = nullptr;
          UINT32 frames = 0;
          DWORD flags = 0;
          if (FAILED(capture_client->GetBuffer(&buffer, &frames, &flags,
                                               nullptr, nullptr))) {
            captured = false;
            break;
          }
          if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
            for (UINT32 frame = 0; frame < frames; ++frame) {
              ring[write_index] = 0.0f;
              write_index = (write_index + 1) % kSampleWindow;
              filled = std::min(filled + 1, kSampleWindow);
            }
          } else if (buffer) {
            for (UINT32 frame = 0; frame < frames; ++frame) {
              float mono = 0.0f;
              for (WORD channel = 0; channel < format->nChannels; ++channel) {
                mono += ReadSample(
                    buffer,
                    static_cast<size_t>(frame) * format->nChannels + channel,
                    format->wBitsPerSample, is_float);
              }
              ring[write_index] = mono / format->nChannels;
              write_index = (write_index + 1) % kSampleWindow;
              filled = std::min(filled + 1, kSampleWindow);
            }
          }
          received_samples = true;
          capture_client->ReleaseBuffer(frames);
          if (FAILED(capture_client->GetNextPacketSize(&packet_frames))) {
            captured = false;
            packet_frames = 0;
            break;
          }
        }

        if (received_samples && filled == kSampleWindow) {
          std::array<float, kSampleWindow> ordered{};
          for (size_t i = 0; i < kSampleWindow; ++i) {
            ordered[i] = ring[(write_index + i) % kSampleWindow];
          }
          const auto bands = AnalyzeBands(ordered, format->nSamplesPerSec);
          std::lock_guard<std::mutex> lock(spectrum_mutex_);
          for (size_t i = 0; i < kBandCount; ++i) {
            spectrum_[i] = spectrum_[i] * 0.35f + bands[i] * 0.65f;
          }
        }
        Sleep(12);
      }
    }

    if (audio_client) audio_client->Stop();
    if (format) CoTaskMemFree(format);
    ReleaseCom(capture_client);
    ReleaseCom(audio_client);
    ReleaseCom(device);
    ReleaseCom(enumerator);

    if (running_.load()) {
      // Clear stale bars during a device switch and allow Windows time to
      // publish the new default endpoint before reconnecting.
      if (!captured) {
        std::lock_guard<std::mutex> lock(spectrum_mutex_);
        spectrum_.fill(0.0f);
      }
      Sleep(500);
    }
  }
  if (uninitialize_com) CoUninitialize();
}
