package cn.pawday;

import cn.pawday.readiness.ProductionAdmissionGuard;
import cn.pawday.settlement.DevelopmentDisbursementPolicy;
import cn.pawday.common.Api;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.mock.env.MockEnvironment;
import static org.junit.jupiter.api.Assertions.*;

class ProductionAdmissionTests {
    @Test void disabledSettlementRejectsBeforeAnyBusinessMutation() {
        var db = org.mockito.Mockito.mock(org.springframework.jdbc.core.JdbcTemplate.class);
        var commands = org.mockito.Mockito.mock(cn.pawday.common.IdempotentCommandExecutor.class);
        var auth = org.mockito.Mockito.mock(cn.pawday.identity.AuthService.class);
        var service = new cn.pawday.settlement.SettlementService(db,null,commands,null,null,auth,java.time.Clock.systemUTC(),new DevelopmentDisbursementPolicy(new MockEnvironment()));
        var actor = new cn.pawday.identity.Actor(java.util.UUID.randomUUID(),cn.pawday.identity.Actor.Realm.ADMIN,null,null,java.util.UUID.randomUUID(),java.util.Set.of("settlement.execute"),java.util.Set.of());
        assertEquals(503,assertThrows(Api.Failure.class,()->service.initiate(actor,java.util.UUID.randomUUID(),"TEST_KEY","TEST_PROOF",null)).status);
        assertEquals(503,assertThrows(Api.Failure.class,()->service.retry(actor,java.util.UUID.randomUUID(),"TEST_KEY","TEST_PROOF",null)).status);
        assertEquals(0,service.retryFailed());
        org.mockito.Mockito.verifyNoInteractions(db,commands,auth);
    }
    @ParameterizedTest @ValueSource(strings={"production","prod","Production"})
    void productionProfilesAreBlockedWithoutAnyDatabase(String profile) {
        var env = new MockEnvironment(); env.setActiveProfiles(profile);
        var failure = assertThrows(IllegalStateException.class, () -> new ProductionAdmissionGuard().postProcessEnvironment(env,null));
        assertTrue(failure.getMessage().startsWith(ProductionAdmissionGuard.MARKER));
        assertTrue(failure.getMessage().contains("NOT_IMPLEMENTED"));
    }
    @Test void productionModeCannotBeBypassedByLocalProfileOrFlags() {
        var env = new MockEnvironment().withProperty("pawday.deployment-mode","production")
            .withProperty("pawday.settlement.simulation-enabled","true").withProperty("pawday.ai.allow-loopback-provider","true")
            .withProperty("pawday.auth.secret-key","TEST_ONLY_DO_NOT_LOG_THIS_SECRET");
        env.setActiveProfiles("local");
        var failure = assertThrows(IllegalStateException.class, () -> new ProductionAdmissionGuard().postProcessEnvironment(env,null));
        assertTrue(failure.getMessage().contains("DEVELOPMENT_PROFILE"));
        assertTrue(failure.getMessage().contains("PAWDAY_AI_ALLOW_LOOPBACK_PROVIDER"));
        assertFalse(failure.getMessage().contains("DO_NOT_LOG"));
    }
    @Test void inventedReadinessFlagCannotUnlockProduction() {
        var env = new MockEnvironment().withProperty("pawday.deployment-mode","production")
            .withProperty("pawday.production-ready","true").withProperty("pawday.live-adapters-ready","true");
        assertThrows(IllegalStateException.class, () -> new ProductionAdmissionGuard().postProcessEnvironment(env,null));
    }
    @Test void unknownDeploymentModeIsRejectedWithoutEchoingValue() {
        var env = new MockEnvironment().withProperty("pawday.deployment-mode","TEST_ONLY_PRIVATE_VALUE");
        var failure = assertThrows(IllegalStateException.class, () -> new ProductionAdmissionGuard().postProcessEnvironment(env,null));
        assertEquals(ProductionAdmissionGuard.MARKER + ": INVALID_DEPLOYMENT_MODE", failure.getMessage());
    }
    @ParameterizedTest @ValueSource(strings={"development","staging"})
    void engineeringEnvironmentsRemainAvailable(String mode) {
        var env = new MockEnvironment().withProperty("pawday.deployment-mode",mode);
        assertDoesNotThrow(() -> new ProductionAdmissionGuard().postProcessEnvironment(env,null));
    }
    @Test void disbursementIsDisabledByDefault() {
        var policy = new DevelopmentDisbursementPolicy(new MockEnvironment());
        assertFalse(policy.enabled());
        var failure = assertThrows(Api.Failure.class,policy::requireEnabled);
        assertEquals(503,failure.status);
    }
    @ParameterizedTest @ValueSource(strings={"production","prod","Production"})
    void productionDisbursementCannotBeEnabled(String profile) {
        var env = new MockEnvironment().withProperty("pawday.settlement.simulation-enabled","true");
        env.setActiveProfiles(profile,"local");
        assertFalse(new DevelopmentDisbursementPolicy(env).enabled());
    }
    @Test void productionModeBlocksDisbursementWithoutProductionProfile() {
        var env = new MockEnvironment().withProperty("pawday.deployment-mode","production").withProperty("pawday.settlement.simulation-enabled","true");
        assertFalse(new DevelopmentDisbursementPolicy(env).enabled());
    }
    @Test void explicitDevelopmentSimulationStillWorks() {
        var policy = new DevelopmentDisbursementPolicy(new MockEnvironment().withProperty("pawday.settlement.simulation-enabled","true"));
        assertTrue(policy.enabled()); assertDoesNotThrow(policy::requireEnabled);
    }
}
