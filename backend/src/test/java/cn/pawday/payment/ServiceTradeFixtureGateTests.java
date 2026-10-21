package cn.pawday.payment;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.env.MockEnvironment;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
class ServiceTradeFixtureGateTests {
 @Test void nonPendingFixtureRequiresExplicitServiceAndBookingFlags(){var db=mock(JdbcTemplate.class);for(var env:new MockEnvironment[]{new MockEnvironment(),new MockEnvironment().withProperty("pawday.booking.simulation-enabled","true"),new MockEnvironment().withProperty("pawday.service-trade.simulation-enabled","true")}){env.withProperty("pawday.service-trade.fixture-outcome","SUCCEEDED");assertThrows(IllegalStateException.class,()->new SimulatedPaymentGateway(db,env));}verifyNoInteractions(db);}
 @ParameterizedTest @ValueSource(strings={"prod","production"}) void configuredSuccessCannotRunUnderProductionProfiles(String profile){var env=new MockEnvironment().withProperty("pawday.booking.simulation-enabled","true").withProperty("pawday.service-trade.simulation-enabled","true").withProperty("pawday.service-trade.fixture-outcome","SUCCEEDED");env.setActiveProfiles(profile);assertThrows(IllegalStateException.class,()->new SimulatedPaymentGateway(mock(JdbcTemplate.class),env));}
 @Test void productionModeAndUnknownOutcomeAreRejected(){for(String mode:new String[]{"production","unrecognized"}){var env=new MockEnvironment().withProperty("pawday.booking.simulation-enabled","true").withProperty("pawday.service-trade.simulation-enabled","true").withProperty("pawday.service-trade.fixture-outcome","SUCCEEDED").withProperty("pawday.deployment-mode",mode);assertThrows(IllegalStateException.class,()->new SimulatedPaymentGateway(mock(JdbcTemplate.class),env));}assertThrows(IllegalStateException.class,()->new SimulatedPaymentGateway(mock(JdbcTemplate.class),new MockEnvironment().withProperty("pawday.service-trade.fixture-outcome","CLIENT_OUTCOME")));}
}
