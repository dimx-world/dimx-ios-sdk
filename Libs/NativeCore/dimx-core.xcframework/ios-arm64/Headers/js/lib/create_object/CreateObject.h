#pragma once
#include <Common.h>
#include <functional>
#include <memory>

class Config;
ConfigPtr createObjectConfig(const Config& config);