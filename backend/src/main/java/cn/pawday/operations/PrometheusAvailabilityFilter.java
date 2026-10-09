package cn.pawday.operations;

import cn.pawday.identity.Actor;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import java.io.IOException;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;

/** After Spring Security. A DB outage must not turn dozens of SQL gauges into a scrape timeout. */
@Component @Order(Ordered.LOWEST_PRECEDENCE)
public final class PrometheusAvailabilityFilter implements Filter {
    private final JdbcTemplate check;
    public PrometheusAvailabilityFilter(javax.sql.DataSource datasource){check=new JdbcTemplate(datasource);check.setQueryTimeout(1);}
    @Override public void doFilter(ServletRequest request,ServletResponse response,FilterChain chain)throws IOException,ServletException {
        var auth=SecurityContextHolder.getContext().getAuthentication();
        boolean allowed=auth!=null && (auth.getPrincipal()==ScrapeCredential.Principal.METRICS || auth.getPrincipal() instanceof Actor a && a.realm()==Actor.Realm.ADMIN && a.permissions().contains("outbox.read"));
        if(request instanceof HttpServletRequest r && response instanceof HttpServletResponse s && r.getRequestURI().equals("/actuator/prometheus") && allowed) {
            try{check.queryForObject("SELECT 1",Integer.class);}
            catch(org.springframework.dao.DataAccessException unavailable){
                s.setStatus(200);s.setContentType("text/plain;version=0.0.4;charset=utf-8");
                s.getWriter().write("# TYPE pawday_operations_db_available gauge\npawday_operations_db_available 0\n");return;
            }
        }
        chain.doFilter(request,response);
    }
}
