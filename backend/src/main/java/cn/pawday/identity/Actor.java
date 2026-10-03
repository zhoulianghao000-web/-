package cn.pawday.identity;

import java.util.Set;
import java.util.UUID;

public record Actor(UUID principalId, Realm realm, UUID userId, UUID merchantId,
                    UUID sessionId, Set<String> permissions, Set<String> roleCodes) {
    public enum Realm { CONSUMER, MERCHANT, ADMIN }
}
