package com.nodecockpit.customization;

import java.nio.charset.StandardCharsets;
import java.util.Locale;

/** Camera metadata verified in the remote media payload of Photos build 52617560. */
final class CloudCameraOrigin {
    static final int PHOTOS_VERSION_CODE = 52617560;
    static final int MAX_PAYLOAD_BYTES = 1024 * 1024;
    private static final int[] CAMERA_FIELDS = {5, 2, 1, 9, 5};

    enum Source { OTHER_DEVICE, SAME_MODEL, UNKNOWN }

    record Camera(String make, String model) {
        String label() {
            return model.startsWith(make + " ") ? model : make + " " + model;
        }
    }

    static Source classify(byte[] payload, String localModel) {
        String expected = normalize(localModel);
        Camera camera = camera(payload);
        if (camera == null || expected.isEmpty()) return Source.UNKNOWN;
        String model = camera.model();
        String vendor = camera.make() + " ";
        if (model.startsWith(vendor)) model = model.substring(vendor.length());
        if (expected.startsWith(vendor)) expected = expected.substring(vendor.length());
        return model.equals(expected) ? Source.SAME_MODEL : Source.OTHER_DEVICE;
    }

    static Camera camera(byte[] payload) {
        if (payload == null || payload.length == 0 || payload.length > MAX_PAYLOAD_BYTES) return null;
        try {
            Slice camera = new Slice(0, payload.length);
            for (int field : CAMERA_FIELDS) {
                camera = bytesField(payload, camera, field);
                if (camera == null) return null;
            }
            String make = textField(payload, camera, 1);
            String model = textField(payload, camera, 2);
            return make.isEmpty() || model.isEmpty() ? null : new Camera(make, model);
        } catch (IllegalArgumentException malformedPayload) {
            return null;
        }
    }

    private static String normalize(String value) {
        if (value == null) return "";
        String name = value.trim().replaceAll("\\s+", " ").toLowerCase(Locale.ROOT);
        if (name.equals("unknown") || name.equals("android") || name.equals("null")) return "";
        return name;
    }

    private static String textField(byte[] data, Slice message, int field) {
        Slice bytes = bytesField(data, message, field);
        if (bytes == null || bytes.end - bytes.start > 128) return "";
        String value = new String(data, bytes.start, bytes.end - bytes.start, StandardCharsets.UTF_8);
        if (value.indexOf('\uFFFD') >= 0 || value.chars().anyMatch(Character::isISOControl)) return "";
        return normalize(value);
    }

    private static Slice bytesField(byte[] data, Slice message, int field) {
        Reader reader = new Reader(data, message);
        Slice result = null;
        while (reader.position < message.end) {
            long tag = reader.varint();
            if (tag < 8 || tag > 0xFFFFFFFFL) throw new IllegalArgumentException("Invalid tag");
            int wire = (int) (tag & 7);
            switch (wire) {
                case 0:
                    reader.varint();
                    break;
                case 1:
                case 5:
                    reader.skip(wire == 1 ? 8 : 4);
                    break;
                case 2:
                    long length = reader.varint();
                    int start = reader.position;
                    reader.skip(length);
                    if ((tag >>> 3) == field) result = new Slice(start, reader.position);
                    break;
                default:
                    throw new IllegalArgumentException("Unsupported wire type");
            }
        }
        return result;
    }

    private static final class Slice {
        final int start;
        final int end;

        Slice(int start, int end) {
            this.start = start;
            this.end = end;
        }
    }

    private static final class Reader {
        final byte[] data;
        final int end;
        int position;

        Reader(byte[] data, Slice slice) {
            this.data = data;
            position = slice.start;
            end = slice.end;
        }

        long varint() {
            long result = 0;
            for (int shift = 0; shift < 64 && position < end; shift += 7) {
                int next = data[position++] & 255;
                if (shift == 63 && next > 1) break;
                result |= (long) (next & 127) << shift;
                if (next < 128) return result;
            }
            throw new IllegalArgumentException("Truncated varint");
        }

        void skip(long length) {
            if (length < 0 || length > end - position) throw new IllegalArgumentException("Truncated field");
            position += (int) length;
        }
    }
}
