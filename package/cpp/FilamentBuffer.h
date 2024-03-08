#pragma once

#include "ManagedBuffer.h"
#include "jsi/HybridObject.h"

namespace margelo {

class FilamentBuffer : public HybridObject {
public:
  explicit FilamentBuffer(const std::shared_ptr<ManagedBuffer>& buffer) : HybridObject("FilamentBuffer"), _buffer(buffer) {}

  void loadHybridMethods() override {}

  const std::shared_ptr<ManagedBuffer>& getBuffer() {
    return _buffer;
  }

private:
  std::shared_ptr<ManagedBuffer> _buffer;
};

} // namespace margelo
