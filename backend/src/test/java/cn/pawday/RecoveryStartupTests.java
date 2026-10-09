package cn.pawday;
import cn.pawday.readiness.RecoveryStartupGuard;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.core.env.*;
import java.util.Map;
import static org.junit.jupiter.api.Assertions.*;
class RecoveryStartupTests {
 @ParameterizedTest @ValueSource(strings={"recovery","restore","LOCAL,RECOVERY","test,restore"}) void profilesCannotStartWorkers(String p){var e=new StandardEnvironment();e.setActiveProfiles(p.split(","));assertEquals(RecoveryStartupGuard.MARKER+": OFFLINE_REVIEW_REQUIRED",assertThrows(IllegalStateException.class,()->new RecoveryStartupGuard().postProcessEnvironment(e,null)).getMessage());}
 @ParameterizedTest @ValueSource(strings={"recovery","restore"}) void modeIsAlsoBlocked(String p){var e=new StandardEnvironment();e.getPropertySources().addFirst(new MapPropertySource("test",Map.of("pawday.deployment-mode",p)));assertThrows(IllegalStateException.class,()->new RecoveryStartupGuard().postProcessEnvironment(e,null));}
 @Test void explicitQuarantineCannotBeOverriddenByDevelopment(){var e=new StandardEnvironment();e.getPropertySources().addFirst(new MapPropertySource("test",Map.of("pawday.recovery.quarantine","true","pawday.deployment-mode","development")));assertThrows(IllegalStateException.class,()->new RecoveryStartupGuard().postProcessEnvironment(e,null));}
 @Test void ordinaryDevelopmentRemainsAvailable(){var e=new StandardEnvironment();e.getPropertySources().addFirst(new MapPropertySource("test",Map.of("pawday.deployment-mode","development")));assertDoesNotThrow(()->new RecoveryStartupGuard().postProcessEnvironment(e,null));}
}
