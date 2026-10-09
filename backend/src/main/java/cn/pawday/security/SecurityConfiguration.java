package cn.pawday.security;

import cn.pawday.identity.*;
import cn.pawday.audit.AuditWriter;
import cn.pawday.common.Api;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.util.*;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.filter.OncePerRequestFilter;
import tools.jackson.databind.json.JsonMapper;

@Configuration
public class SecurityConfiguration {
    @Bean org.springframework.security.core.userdetails.UserDetailsService disabledDefaultUserService() {
        return username->{throw new org.springframework.security.core.userdetails.UsernameNotFoundException("No framework default accounts");};
    }
    @Bean SecurityFilterChain security(HttpSecurity http,AuthService auth,AuditWriter audit,cn.pawday.operations.ScrapeCredential scrape) throws Exception {
        var filter=new BoundaryFilter(auth,audit,scrape);
        return http.csrf(c->c.disable()) // Only Authorization bearer; no cookie/HTTP-session credentials are accepted.
            .httpBasic(c->c.disable()).formLogin(c->c.disable()).logout(c->c.disable())
            .sessionManagement(c->c.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .exceptionHandling(c->c.authenticationEntryPoint((r,s,e)->filter.deny(r,s,401,"AUTH_REQUIRED",null))
                .accessDeniedHandler((r,s,e)->filter.deny(r,s,403,"PERMISSION_DENIED",current())))
            .authorizeHttpRequests(c->c
                .requestMatchers("/actuator/health","/actuator/health/**","/error").permitAll()
                .requestMatchers("/actuator/prometheus","/actuator/metrics","/actuator/metrics/**").access((a,cx)->new org.springframework.security.authorization.AuthorizationDecision(a.get().getPrincipal()==cn.pawday.operations.ScrapeCredential.Principal.METRICS || a.get().getPrincipal() instanceof Actor actor && actor.realm()==Actor.Realm.ADMIN && actor.permissions().contains("outbox.read")))
                .requestMatchers("/api/v1/media/**").authenticated()
                .requestMatchers("/api/v1/public/**").permitAll()
                .requestMatchers("/api/v1/consumer/auth/phone/request-code","/api/v1/consumer/auth/phone/verify",
                    "/api/v1/merchant/auth/login","/api/v1/admin/auth/login",
                    "/api/v1/consumer/auth/refresh","/api/v1/merchant/auth/refresh","/api/v1/admin/auth/refresh").permitAll()
                .requestMatchers("/api/v1/consumer/**").access((a,cx)->new org.springframework.security.authorization.AuthorizationDecision(hasRealm(a.get().getPrincipal(),Actor.Realm.CONSUMER)))
                .requestMatchers("/api/v1/merchant/**").access((a,cx)->new org.springframework.security.authorization.AuthorizationDecision(hasRealm(a.get().getPrincipal(),Actor.Realm.MERCHANT)))
                .requestMatchers("/api/v1/admin/**").access((a,cx)->new org.springframework.security.authorization.AuthorizationDecision(hasRealm(a.get().getPrincipal(),Actor.Realm.ADMIN)))
                .anyRequest().denyAll())
            .addFilterBefore(filter,UsernamePasswordAuthenticationFilter.class).build();
    }
    private static boolean hasRealm(Object principal,Actor.Realm realm) {return principal instanceof Actor actor && actor.realm()==realm;}
    private static Actor current() {var a=SecurityContextHolder.getContext().getAuthentication();return a!=null && a.getPrincipal() instanceof Actor actor?actor:null;}
    static final class BoundaryFilter extends OncePerRequestFilter {
        private final AuthService auth;private final AuditWriter audit;private final JsonMapper json=JsonMapper.builder().build();
        private final cn.pawday.operations.ScrapeCredential scrape;
        BoundaryFilter(AuthService auth,AuditWriter audit,cn.pawday.operations.ScrapeCredential scrape){this.auth=auth;this.audit=audit;this.scrape=scrape;}
        void deny(HttpServletRequest r,HttpServletResponse s,int status,String code,Actor actor) throws IOException {
            try {audit.write(actor,"security.denied","HTTP_REQUEST",null,Map.of(),Map.of("failure_reason",code,"http_status",status),r);}
            catch(org.springframework.dao.DataAccessException unavailable) {status=503;code="PERSISTENCE_UNAVAILABLE";}
            s.setStatus(status);s.setContentType("application/json");s.getWriter().write(json.writeValueAsString(Api.error(code,r)));
        }
        @Override protected void doFilterInternal(HttpServletRequest r,HttpServletResponse s,FilterChain chain) throws IOException,ServletException {
            String requestId=UUID.randomUUID().toString(),correlation=r.getHeader("X-Correlation-Id");
            try {correlation=UUID.fromString(correlation).toString();}catch(Exception ignored){correlation=requestId;}
            r.setAttribute("request_id",requestId);r.setAttribute("correlation_id",correlation);
            s.setHeader("X-Request-Id",requestId);s.setHeader("X-Correlation-Id",correlation);
            String header=r.getHeader("Authorization");
            if(scrape.accepts(r.getRequestURI(),header)) {
                SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(cn.pawday.operations.ScrapeCredential.Principal.METRICS,null,List.of()));
            } else if(header!=null) {
                if(!header.startsWith("Bearer ")) {deny(r,s,401,"TOKEN_EXPIRED",null);return;}
                Optional<Actor> actor;
                try {actor=auth.load(header.substring(7));}
                catch(org.springframework.dao.DataAccessException unavailable) {
                    s.setStatus(503);s.setContentType("application/json");s.getWriter().write(json.writeValueAsString(Api.error("PERSISTENCE_UNAVAILABLE",r)));return;
                }
                if(actor.isEmpty()) {deny(r,s,401,"TOKEN_EXPIRED",null);return;}
                SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(actor.get(),null,List.of()));
            }
            try {chain.doFilter(r,s);}finally {SecurityContextHolder.clearContext();}
        }
    }
}
