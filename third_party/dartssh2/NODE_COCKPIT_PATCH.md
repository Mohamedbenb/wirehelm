# Local dartssh2 patch

Base: dartssh2 4.1.0, copied from the resolved pub cache, with its MIT license.

`SSHTransport._processPackets` yields to the event queue after a 4 ms processing slice. The yield occurs after a complete packet's message handling and sequence-number/rekey bookkeeping. The existing `_isProcessingData` guard remains active across the yield, preserving serial parsing. This prevents a continuously buffered SSH transfer from monopolizing Flutter's UI isolate through completed-future microtasks.

The app uses a workspace path override, so this patch survives clean builds and does not change the shared pub cache. Re-evaluate the patch when upgrading dartssh2. No cipher, authentication, packet ordering or security checks are changed.

Build 11 exposes the negotiated incoming cipher name through read-only SSHTransport/SSHClient getters. Cipher preference is configured by the app connection service, not by changing library defaults.

Build 12 fixes `ChunkBuffer.add` capacity growth during fragmented transfers. When the write cursor reaches the end, compaction now retains the existing capacity if most of it has already been consumed and the incoming chunk fits. Capacity still grows when needed, or when most existing bytes remain live so a sliding full buffer keeps spare append space. Previously, an incomplete packet surviving each native read could cause the allocation to grow toward the total transfer size even with less than one packet buffered. Compaction still allocates fresh storage, preserving exposed views and byte order. Regressions simulate a 42 MiB transfer with mismatched receive/packet boundaries and verify a maximum 128 KiB backing allocation, check views across compaction and growth, and cover a nearly full sliding buffer.
