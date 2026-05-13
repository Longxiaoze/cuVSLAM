
/*
 * Copyright (c) 2026, NVIDIA CORPORATION. All rights reserved.
 *
 * NVIDIA software released under the NVIDIA Community License is intended to be used to enable
 * the further development of AI and robotics technologies. Such software has been designed, tested,
 * and optimized for use with NVIDIA hardware, and this License grants permission to use the software
 * solely with such hardware.
 * Subject to the terms of this License, NVIDIA confirms that you are free to commercially use,
 * modify, and distribute the software with NVIDIA hardware. NVIDIA does not claim ownership of any
 * outputs generated using the software or derivative works thereof. Any code contributions that you
 * share with NVIDIA are licensed to NVIDIA as feedback under this License and may be incorporated
 * in future releases without notice or attribution.
 * By using, reproducing, modifying, distributing, performing, or displaying any portion or element
 * of the software or derivative works thereof, you agree to be bound by this License.
 */

#include "camera_rig_edex/blackout_oscillator_filter.h"

#include <cstdint>
#include <cstring>

#include "common/imu_measurement.h"
#include "common/log.h"

namespace cuvslam::camera_rig_edex {

BlackoutOscillatorFilter::BlackoutOscillatorFilter(std::unique_ptr<ICameraRig>&& base, int period, int duration)
    : base_(std::move(base)), period_(period), duration_(duration) {
  assert(period > duration);
}

ErrorCode BlackoutOscillatorFilter::start() { return base_->start(); }

ErrorCode BlackoutOscillatorFilter::stop() { return base_->stop(); }

const camera::ICameraModel& BlackoutOscillatorFilter::getIntrinsic(uint32_t index) const {
  return base_->getIntrinsic(index);
}

const Isometry3T& BlackoutOscillatorFilter::getExtrinsic(uint32_t index) const { return base_->getExtrinsic(index); }

ErrorCode BlackoutOscillatorFilter::getFrame(Sources& sources, Metas& metas, Sources& masks_sources,
                                             DepthSources& depth_sources) {
  ErrorCode status = base_->getFrame(sources, metas, masks_sources, depth_sources);

  assert(sources.size() == metas.size());

  if (status == ErrorCode::S_True && !metas.empty()) {
    int frame_id = static_cast<int>(metas.begin()->second.frame_id);
    int index = frame_id % period_;
    if (index < duration_ && frame_id >= period_) {
      const auto image_size_bytes = [](const ImageSource& source, const ImageShape& shape) {
        switch (source.type) {
          case ImageSource::U8:
            return static_cast<size_t>(shape.width) * shape.height *
                   (source.image_encoding == ImageEncoding::RGB8 ? 3 : 1);
          case ImageSource::F32:
            return static_cast<size_t>(shape.width) * shape.height * sizeof(float);
          case ImageSource::U16:
            return static_cast<size_t>(shape.width) * shape.height * sizeof(uint16_t);
        }
        return size_t{0};
      };

      // do blackout
      for (auto& [cam_id, source] : sources) {
        const auto meta_it = metas.find(cam_id);
        if (meta_it != metas.end() && source.data != nullptr) {
          std::memset(source.data, 0, image_size_bytes(source, meta_it->second.shape));
        }
      }
      for (auto& [cam_id, source] : depth_sources) {
        const auto meta_it = metas.find(cam_id);
        if (meta_it != metas.end() && source.data != nullptr) {
          std::memset(source.data, 0, image_size_bytes(source, meta_it->second.shape));
        }
      }
      log::Value<LogRoot>("blackout_oscilator", true);
    } else {
      log::Value<LogRoot>("blackout_oscilator", false);
    }
  }

  return status;
}

void BlackoutOscillatorFilter::registerIMUCallback(
    const std::function<void(const imu::ImuMeasurement& integrator)>& func) {
  base_->registerIMUCallback(func);
}

}  // namespace cuvslam::camera_rig_edex
