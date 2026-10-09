package cn.pawday.readiness;

import java.util.*;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.env.EnvironmentPostProcessor;
import org.springframework.core.Ordered;
import org.springframework.core.env.ConfigurableEnvironment;

/** Recovery is an offline quarantine, never an application/worker startup mode. */
public final class RecoveryStartupGuard implements EnvironmentPostProcessor, Ordered {
 public static final String MARKER="PAWDAY_RECOVERY_QUARANTINE_BLOCKED";
 public int getOrder(){return Ordered.LOWEST_PRECEDENCE-1;}
 public void postProcessEnvironment(ConfigurableEnvironment env,SpringApplication app){
  boolean profile=Arrays.stream(env.getActiveProfiles()).anyMatch(p->Set.of("recovery","restore").contains(p.toLowerCase(Locale.ROOT)));
  String mode=env.getProperty("pawday.deployment-mode","development");
  if(profile || Set.of("recovery","restore").contains(mode.toLowerCase(Locale.ROOT)) || Boolean.parseBoolean(env.getProperty("pawday.recovery.quarantine","false")))
   throw new IllegalStateException(MARKER+": OFFLINE_REVIEW_REQUIRED");
 }
}
