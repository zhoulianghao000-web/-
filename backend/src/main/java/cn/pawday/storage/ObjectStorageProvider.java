package cn.pawday.storage;

import java.io.InputStream;
import java.util.Optional;

/** Business code depends on this contract, never a cloud SDK or a bucket name. */
public interface ObjectStorageProvider {
    record Put(String objectKey,String mime,long sizeBytes,String sha256,long maxBytes) {}
    record Metadata(String objectKey,String mime,long sizeBytes,String sha256) {}
    /** Optional adapter housekeeping; no business object deletion. */
    default int reapAbandonedUploads(java.time.Instant olderThan){return 0;}
    String providerId();
    Metadata put(Put request,InputStream content);
    Optional<Metadata> metadata(String objectKey);
    InputStream read(String objectKey);
    /** Delete is idempotent, including when the key was never uploaded. */
    void delete(String objectKey);
}
