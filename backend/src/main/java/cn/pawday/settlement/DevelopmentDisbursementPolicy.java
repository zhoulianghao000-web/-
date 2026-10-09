package cn.pawday.settlement;

import cn.pawday.common.Api.Failure;
import java.util.Arrays;
import java.util.Locale;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

/** The existing in-database disbursement is a simulator, never a production payout. */
@Component
public final class DevelopmentDisbursementPolicy {
    private final boolean enabled;
    public DevelopmentDisbursementPolicy(Environment env) {
        boolean production = Arrays.stream(env.getActiveProfiles())
            .map(s -> s.toLowerCase(Locale.ROOT)).anyMatch(s -> s.equals("production") || s.equals("prod"));
        production |= "production".equalsIgnoreCase(env.getProperty("pawday.deployment-mode", "development"));
        enabled = !production && "true".equalsIgnoreCase(env.getProperty("pawday.settlement.simulation-enabled", "false"));
    }
    public boolean enabled() { return enabled; }
    public void requireEnabled() { if (!enabled) throw new Failure(503, "SETTLEMENT_PROVIDER_UNAVAILABLE"); }
}
