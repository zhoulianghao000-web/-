package cn.pawday.readiness;

import java.util.*;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.env.EnvironmentPostProcessor;
import org.springframework.core.Ordered;
import org.springframework.core.env.ConfigurableEnvironment;

/** Runs after config data, before a datasource, Flyway or an HTTP server can start.
 * No property can attest that a missing live adapter has been implemented. */
public final class ProductionAdmissionGuard implements EnvironmentPostProcessor, Ordered {
    public static final String MARKER = "PAWDAY_PRODUCTION_ADMISSION_BLOCKED";
    @Override public int getOrder() { return Ordered.LOWEST_PRECEDENCE; }
    @Override public void postProcessEnvironment(ConfigurableEnvironment env, SpringApplication app) {
        var profiles = Arrays.stream(env.getActiveProfiles()).map(s -> s.toLowerCase(Locale.ROOT)).toList();
        String mode = env.getProperty("pawday.deployment-mode", "development").toLowerCase(Locale.ROOT);
        if (!Set.of("development", "staging", "production").contains(mode))
            throw new IllegalStateException(MARKER + ": INVALID_DEPLOYMENT_MODE");
        if (!mode.equals("production") && !profiles.contains("production") && !profiles.contains("prod")) return;
        var reasons = new ArrayList<String>();
        // This release has no live payment/refund, SMS, storage or disbursement implementations.
        // M6.2+ must change code and pass real provider gates; an env flag cannot bypass this lock.
        reasons.add("LIVE_PAYMENT_REFUND_SMS_STORAGE_DISBURSEMENT_NOT_IMPLEMENTED");
        if (profiles.stream().anyMatch(Set.of("local", "test", "dev")::contains)) reasons.add("DEVELOPMENT_PROFILE");
        for (String key : List.of("pawday.demo.enabled", "pawday.auth.local-sms-enabled",
                "pawday.payment.simulation-enabled", "pawday.settlement.simulation-enabled",
                "pawday.ai.allow-loopback-provider"))
            if ("true".equalsIgnoreCase(env.getProperty(key))) reasons.add(key.toUpperCase(Locale.ROOT).replace('.', '_').replace('-', '_'));
        // Only fixed reason identifiers, never profiles, endpoints, credential values or config dumps.
        throw new IllegalStateException(MARKER + ": " + String.join(",", reasons));
    }
}
