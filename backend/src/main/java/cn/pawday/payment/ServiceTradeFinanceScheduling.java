package cn.pawday.payment;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.EnableScheduling;

/** Service refund recovery remains available when unrelated outbox delivery is disabled. */
@Configuration
@EnableScheduling
@Profile("!prod & !production")
@ConditionalOnProperty(prefix="pawday.service-trade",name={"simulation-enabled","finance-recovery-enabled"},havingValue="true")
public class ServiceTradeFinanceScheduling {}
