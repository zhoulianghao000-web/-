package cn.pawday;
import cn.pawday.operations.*;
import java.sql.SQLException;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.*;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PrometheusAvailabilityTests {
    @Test void unavailableDatabaseStillExportsAuthenticatedFailureMetric()throws Exception{
        var ds=mock(javax.sql.DataSource.class);when(ds.getConnection()).thenThrow(new SQLException("TEST_ONLY_PRIVATE_CONNECTION"));
        var filter=new PrometheusAvailabilityFilter(ds);var request=new MockHttpServletRequest("GET","/actuator/prometheus");var response=new MockHttpServletResponse();
        SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(ScrapeCredential.Principal.METRICS,null,java.util.List.of()));
        try{filter.doFilter(request,response,(r,s)->fail("SQL gauges must not be evaluated during outage"));assertEquals(200,response.getStatus());assertTrue(response.getContentAsString().contains("pawday_operations_db_available 0"));assertFalse(response.getContentAsString().contains("PRIVATE_CONNECTION"));}
        finally{SecurityContextHolder.clearContext();}
    }
    @Test void failureMetricNeverBypassesAuthentication()throws Exception{
        var ds=mock(javax.sql.DataSource.class);var filter=new PrometheusAvailabilityFilter(ds);var chain=new java.util.concurrent.atomic.AtomicBoolean();
        filter.doFilter(new MockHttpServletRequest("GET","/actuator/prometheus"),new MockHttpServletResponse(),(r,s)->chain.set(true));assertTrue(chain.get());verifyNoInteractions(ds);
    }
}
