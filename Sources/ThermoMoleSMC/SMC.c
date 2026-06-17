// ThermoMole SMC reader.
//
// Talks to the AppleSMC kernel service through the public IOKit user-client
// protocol: match "AppleSMC", open a connection, and issue the two struct
// calls (read key info, then read bytes) that the driver expects. This protocol
// and the SMCKeyData_t layout are the long-public, reverse-engineered SMC ABI
// shared by every SMC reader on macOS; the code here is written for ThermoMole.
#include "ThermoMoleSMC.h"
#include <string.h>

// SMC keys and data-type tags are four-character codes packed big-endian into a
// u32. Folding them through one helper keeps the call sites readable.
static uint32_t smc_fourcc(const char *tag) {
  return ((uint32_t)(unsigned char)tag[0] << 24) |
         ((uint32_t)(unsigned char)tag[1] << 16) |
         ((uint32_t)(unsigned char)tag[2] << 8) |
         (uint32_t)(unsigned char)tag[3];
}

io_connect_t SMCOpen(void) {
  CFMutableDictionaryRef match = IOServiceMatching("AppleSMC");
  io_iterator_t iterator = 0;
  if (IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) != kIOReturnSuccess) {
    return 0;
  }

  io_object_t service = IOIteratorNext(iterator);
  IOObjectRelease(iterator);
  if (service == 0) {
    return 0;
  }

  io_connect_t conn = 0;
  kern_return_t rc = IOServiceOpen(service, mach_task_self(), 0, &conn);
  IOObjectRelease(service);
  return rc == kIOReturnSuccess ? conn : 0;
}

kern_return_t SMCClose(io_connect_t conn) {
  return IOServiceClose(conn);
}

// One round-trip of the SMC user-client struct method.
static kern_return_t smc_call(io_connect_t conn, SMCKeyData_t *in, SMCKeyData_t *out) {
  size_t in_size = sizeof(SMCKeyData_t);
  size_t out_size = sizeof(SMCKeyData_t);
  return IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, in, in_size, out, &out_size);
}

kern_return_t SMCReadKey(io_connect_t conn, const char *key, SMCKeyData_t *val) {
  if (conn == 0 || key == NULL || strlen(key) < 4 || val == NULL) {
    return kIOReturnBadArgument;
  }

  SMCKeyData_t request;
  SMCKeyData_t response;
  memset(&request, 0, sizeof(request));
  memset(&response, 0, sizeof(response));
  memset(val, 0, sizeof(*val));

  request.key = smc_fourcc(key);

  // First call resolves the key's size/type metadata.
  request.data8 = SMC_CMD_READ_KEYINFO;
  kern_return_t rc = smc_call(conn, &request, &response);
  if (rc != kIOReturnSuccess) {
    return rc;
  }

  // The keyinfo response carries the size/type metadata; capture it now. The
  // READ_BYTES response below does NOT re-report dataType, so it must be read
  // from this (READ_KEYINFO) response.
  val->keyInfo = response.keyInfo;

  // Second call pulls the raw bytes for that key, sized by the metadata above.
  request.keyInfo.dataSize = val->keyInfo.dataSize;
  request.data8 = SMC_CMD_READ_BYTES;
  rc = smc_call(conn, &request, &response);
  if (rc != kIOReturnSuccess) {
    return rc;
  }

  memcpy(val->bytes, response.bytes, sizeof(val->bytes));
  return kIOReturnSuccess;
}

double SMCGetFloatValue(io_connect_t conn, const char *key) {
  SMCKeyData_t val;
  if (SMCReadKey(conn, key, &val) != kIOReturnSuccess) {
    return 0.0;
  }

  // IEEE-754 single precision, little-endian in the SMC payload.
  if (val.keyInfo.dataType == smc_fourcc("flt ")) {
    float f = 0.0f;
    memcpy(&f, val.bytes, sizeof(f));
    return (double)f;
  }

  // Signed 7.8 fixed point: high byte integer part, low byte 1/256 fraction.
  if (val.keyInfo.dataType == smc_fourcc("sp78")) {
    int16_t fixed = (int16_t)(((unsigned char)val.bytes[0] << 8) | (unsigned char)val.bytes[1]);
    return (double)fixed / 256.0;
  }

  return 0.0;
}
