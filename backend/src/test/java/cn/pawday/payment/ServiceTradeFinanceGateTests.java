package cn.pawday.payment;

import cn.pawday.common.Api.Failure;
import cn.pawday.pilot.PilotPolicy;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.mock.env.MockEnvironment;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class ServiceTradeFinanceGateTests {
 private ServiceTradeFinance service(MockEnvironment env,PilotPolicy pilot,ObjectProvider<PaymentGateway> providers){return new ServiceTradeFinance(null,null,null,providers,null,null,null,null,null,pilot,env);}
 private MockEnvironment enabled(){return new MockEnvironment().withProperty("pawday.booking.simulation-enabled","true").withProperty("pawday.service-trade.simulation-enabled","true").withProperty("pawday.payment.simulation-enabled","true");}
 @Test void defaultOffRejectsAllChannelAccessBeforeProviderResolution(){var providers=mock(ObjectProvider.class);var f=service(new MockEnvironment(),mock(PilotPolicy.class),providers);assertEquals(404,assertThrows(Failure.class,f::channelGate).status);verifyNoInteractions(providers);assertEquals(0,f.recoverBatch());}
 @ParameterizedTest @ValueSource(strings={"production","prod"}) void activeProductionProfilesDenySimulationEvenWithFlags(String profile){var env=enabled();env.setActiveProfiles(profile,"local");var providers=mock(ObjectProvider.class);var f=service(env,mock(PilotPolicy.class),providers);assertEquals(404,assertThrows(Failure.class,f::channelGate).status);assertEquals(0,f.recoverBatch());verifyNoInteractions(providers);}
 @Test void productionDeploymentModeDeniesSimulation(){var f=service(enabled().withProperty("pawday.deployment-mode","production"),mock(PilotPolicy.class),mock(ObjectProvider.class));assertEquals(404,assertThrows(Failure.class,f::channelGate).status);}
 @Test void disabledPaymentFlagAndPauseRetainRecoveryWork(){var pilot=mock(PilotPolicy.class);var f=service(enabled().withProperty("pawday.payment.simulation-enabled","false"),pilot,mock(ObjectProvider.class));assertEquals("SERVICE_PAYMENT_SIMULATION_DISABLED",assertThrows(Failure.class,f::channelGate).code);assertEquals(0,f.recoverBatch());when(pilot.paused()).thenReturn(true);var paused=service(enabled(),pilot,mock(ObjectProvider.class));assertEquals(503,assertThrows(Failure.class,paused::channelGate).status);assertEquals(0,paused.recoverBatch());}
 @Test void realOrUnknownGatewayCannotBeUsedForServiceMoney(){ObjectProvider<PaymentGateway> providers=mock(ObjectProvider.class);when(providers.getIfAvailable()).thenReturn(mock(PaymentGateway.class));var f=service(enabled(),mock(PilotPolicy.class),providers);assertEquals("SERVICE_SIMULATED_PROVIDER_REQUIRED",assertThrows(Failure.class,f::channelGate).code);assertEquals(0,f.recoverBatch());verifyNoInteractions(providers.getIfAvailable());}
}
