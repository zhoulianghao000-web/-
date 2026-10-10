package cn.pawday.privacy;

/** Independent durability boundary. Never use the business DB or media bucket. */
public interface PrivacyExportProvider {
    void publish(PrivacyExportService.Checkpoint checkpoint);
}
