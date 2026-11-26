// Minimal MessagePack encoder/decoder for JSON-like balance sheets (maps, arrays, strings, numbers, bools, null).
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

function encodeValue(value: unknown, out: number[]): void {
  if (value === null) {
    out.push(0xc0);
    return;
  }
  if (value === false) {
    out.push(0xc2);
    return;
  }
  if (value === true) {
    out.push(0xc3);
    return;
  }
  if (typeof value === "number") {
    const bytes = new Uint8Array(9);
    const view = new DataView(bytes.buffer);
    bytes[0] = 0xcb;
    view.setFloat64(1, value);
    out.push(...bytes);
    return;
  }
  if (typeof value === "string") {
    const utf8 = textEncoder.encode(value);
    if (utf8.length < 32) {
      out.push(0xa0 + utf8.length, ...utf8);
    } else if (utf8.length < 256) {
      out.push(0xd9, utf8.length, ...utf8);
    } else {
      out.push(0xda, (utf8.length >> 8) & 0xff, utf8.length & 0xff, ...utf8);
    }
    return;
  }
  if (Array.isArray(value)) {
    if (value.length < 16) out.push(0x90 + value.length);
    else out.push(0xdc, (value.length >> 8) & 0xff, value.length & 0xff);
    for (const item of value) encodeValue(item, out);
    return;
  }
  if (typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>);
    if (entries.length < 16) out.push(0x80 + entries.length);
    else out.push(0xde, (entries.length >> 8) & 0xff, entries.length & 0xff);
    for (const [key, item] of entries) {
      encodeValue(key, out);
      encodeValue(item, out);
    }
  }
}

export function encodeMsgpack(value: unknown): Uint8Array {
  const out: number[] = [];
  encodeValue(value, out);
  return Uint8Array.from(out);
}

function read(buf: Uint8Array, cursor: { i: number }): unknown {
  const byte = buf[cursor.i++];
  if (byte === 0xc0) return null;
  if (byte === 0xc2) return false;
  if (byte === 0xc3) return true;
  if (byte === 0xcb) {
    const view = new DataView(buf.buffer, buf.byteOffset + cursor.i, 8);
    cursor.i += 8;
    return view.getFloat64(0);
  }
  if (byte >= 0xa0 && byte <= 0xbf) {
    const length = byte - 0xa0;
    const slice = buf.subarray(cursor.i, cursor.i + length);
    cursor.i += length;
    return textDecoder.decode(slice);
  }
  if (byte === 0xd9) {
    const length = buf[cursor.i++];
    const slice = buf.subarray(cursor.i, cursor.i + length);
    cursor.i += length;
    return textDecoder.decode(slice);
  }
  if (byte === 0xda) {
    const length = (buf[cursor.i++] << 8) + buf[cursor.i++];
    const slice = buf.subarray(cursor.i, cursor.i + length);
    cursor.i += length;
    return textDecoder.decode(slice);
  }
  if (byte >= 0x90 && byte <= 0x9f) {
    const length = byte - 0x90;
    return Array.from({ length }, () => read(buf, cursor));
  }
  if (byte === 0xdc) {
    const length = (buf[cursor.i++] << 8) + buf[cursor.i++];
    return Array.from({ length }, () => read(buf, cursor));
  }
  if (byte >= 0x80 && byte <= 0x8f) {
    const length = byte - 0x80;
    const object: Record<string, unknown> = {};
    for (let i = 0; i < length; i += 1) {
      const key = String(read(buf, cursor));
      object[key] = read(buf, cursor);
    }
    return object;
  }
  if (byte === 0xde) {
    const length = (buf[cursor.i++] << 8) + buf[cursor.i++];
    const object: Record<string, unknown> = {};
    for (let i = 0; i < length; i += 1) {
      const key = String(read(buf, cursor));
      object[key] = read(buf, cursor);
    }
    return object;
  }
  throw new Error(`Unsupported MessagePack byte 0x${byte.toString(16)}`);
}

export function decodeMsgpack(buffer: Uint8Array): unknown {
  return read(buffer, { i: 0 });
}
