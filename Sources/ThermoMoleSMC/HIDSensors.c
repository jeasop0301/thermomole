// Reads internal SSD/NAND temperature from the IOHIDEvent temperature sensors.
// Apple Silicon exposes these as HID services (PrimaryUsagePage 0xFF00, PrimaryUsage 5,
// e.g. "NAND CH0 temp") rather than via ioreg static properties or AppleSMC keys.
// The IOHIDEventSystemClient symbols are exported by IOKit but absent from the public SDK
// headers, so they are resolved at runtime with dlsym — this never breaks the link and
// degrades gracefully (returns < 0) if the symbols or sensors are unavailable.
#include "ThermoMoleSMC.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <string.h>

#define THERMOMOLE_HID_TEMPERATURE_TYPE 15
#define THERMOMOLE_HID_TEMPERATURE_FIELD (THERMOMOLE_HID_TEMPERATURE_TYPE << 16)
#define THERMOMOLE_HID_PAGE_APPLE_VENDOR 0xff00
#define THERMOMOLE_HID_USAGE_TEMPERATURE 5

typedef CFTypeRef (*ClientCreate_fn)(CFAllocatorRef);
typedef void (*ClientSetMatching_fn)(CFTypeRef, CFDictionaryRef);
typedef CFArrayRef (*ClientCopyServices_fn)(CFTypeRef);
typedef CFTypeRef (*ServiceCopyProperty_fn)(CFTypeRef, CFStringRef);
typedef CFTypeRef (*ServiceCopyEvent_fn)(CFTypeRef, int64_t, int32_t, int64_t);
typedef double (*EventGetFloatValue_fn)(CFTypeRef, int32_t);

double SSDTemperatureCelsius(void) {
  double result = -1.0;

  void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
  if (!iokit) {
    return result;
  }

  ClientCreate_fn clientCreate = (ClientCreate_fn)dlsym(iokit, "IOHIDEventSystemClientCreate");
  ClientSetMatching_fn setMatching = (ClientSetMatching_fn)dlsym(iokit, "IOHIDEventSystemClientSetMatching");
  ClientCopyServices_fn copyServices = (ClientCopyServices_fn)dlsym(iokit, "IOHIDEventSystemClientCopyServices");
  ServiceCopyProperty_fn copyProperty = (ServiceCopyProperty_fn)dlsym(iokit, "IOHIDServiceClientCopyProperty");
  ServiceCopyEvent_fn copyEvent = (ServiceCopyEvent_fn)dlsym(iokit, "IOHIDServiceClientCopyEvent");
  EventGetFloatValue_fn getFloat = (EventGetFloatValue_fn)dlsym(iokit, "IOHIDEventGetFloatValue");

  if (!clientCreate || !setMatching || !copyServices || !copyProperty || !copyEvent || !getFloat) {
    return result;
  }

  CFTypeRef client = clientCreate(kCFAllocatorDefault);
  if (!client) {
    return result;
  }

  int page = THERMOMOLE_HID_PAGE_APPLE_VENDOR;
  int usage = THERMOMOLE_HID_USAGE_TEMPERATURE;
  CFNumberRef pageNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &page);
  CFNumberRef usageNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);
  if (!pageNumber || !usageNumber) {
    if (pageNumber) CFRelease(pageNumber);
    if (usageNumber) CFRelease(usageNumber);
    CFRelease(client);
    return result;
  }
  const void *keys[] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage")};
  const void *values[] = {pageNumber, usageNumber};
  CFDictionaryRef matching = CFDictionaryCreate(
      kCFAllocatorDefault, keys, values, 2,
      &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

  setMatching(client, matching);
  CFArrayRef services = copyServices(client);

  if (services) {
    double hottest = -1.0;
    CFIndex count = CFArrayGetCount(services);
    for (CFIndex i = 0; i < count; i++) {
      CFTypeRef service = CFArrayGetValueAtIndex(services, i);
      if (!service) {
        continue;
      }
      CFStringRef product = (CFStringRef)copyProperty(service, CFSTR("Product"));
      int isStorage = 0;
      if (product) {
        char name[160];
        if (CFStringGetCString(product, name, sizeof(name), kCFStringEncodingUTF8)) {
          if (strstr(name, "NAND") || strstr(name, "SSD")) {
            isStorage = 1;
          }
        }
        CFRelease(product);
      }
      if (!isStorage) {
        continue;
      }
      CFTypeRef event = copyEvent(service, THERMOMOLE_HID_TEMPERATURE_TYPE, 0, 0);
      if (event) {
        double temp = getFloat(event, THERMOMOLE_HID_TEMPERATURE_FIELD);
        CFRelease(event);
        if (temp > hottest) {
          hottest = temp;
        }
      }
    }
    result = hottest;
    CFRelease(services);
  }

  CFRelease(matching);
  CFRelease(pageNumber);
  CFRelease(usageNumber);
  CFRelease(client);
  return result;
}
