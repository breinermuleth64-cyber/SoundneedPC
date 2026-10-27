#ifndef RUNNER_AUDIO_SPECTRUM_CAPTURE_H_
#define RUNNER_AUDIO_SPECTRUM_CAPTURE_H_

#include <array>
#include <atomic>
#include <mutex>
#include <thread>
#include <vector>

class AudioSpectrumCapture {
 public:
  AudioSpectrumCapture() = default;
  ~AudioSpectrumCapture();

  void Start();
  void Stop();
  std::vector<double> GetSpectrum() const;

 private:
  void CaptureLoop();

  std::atomic<bool> running_{false};
  std::thread capture_thread_;
  mutable std::mutex spectrum_mutex_;
  std::array<float, 32> spectrum_{};
};

#endif  // RUNNER_AUDIO_SPECTRUM_CAPTURE_H_
