package cn.pawday.outbox;
import java.util.UUID;
/** Module-owned dead effect replay hooks; called within the protected PostgreSQL replay transaction. */
public interface OutboxReplayParticipant {
    boolean hasFailed(UUID eventId);
    void resetFailed(UUID eventId,int generation);
}
