package cn.pawday.identity;

@FunctionalInterface
public interface SmsGateway {
    // challengeId is the provider idempotency key. An adapter must reuse it on retries,
    // return the existing receipt or query an ambiguous result; never create a new send key.
    void send(String challengeId,String phone,String code);
}
