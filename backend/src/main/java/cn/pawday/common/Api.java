package cn.pawday.common;

import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.http.converter.HttpMessageNotReadableException;

public final class Api {
    private Api() {}
    public record Meta(String request_id, String correlation_id) {}
    public record Envelope<T>(T data, Meta meta) {}
    public record Page(String next_cursor,boolean has_more) {}
    public record ListEnvelope<T>(java.util.List<T> data,Page page,Meta meta) {}
    public record Error(String code, String message, boolean retryable, Map<String,Object> details) {}
    public record ErrorEnvelope(Error error, Meta meta) {}
    public static Meta meta(HttpServletRequest r) {
        return new Meta((String)r.getAttribute("request_id"),(String)r.getAttribute("correlation_id"));
    }
    public static <T> Envelope<T> ok(T data,HttpServletRequest r) { return new Envelope<>(data,meta(r)); }
    public static <T> ListEnvelope<T> list(java.util.List<T> data,HttpServletRequest r) {return new ListEnvelope<>(data,new Page(null,false),meta(r));}
    public static ErrorEnvelope error(String code,HttpServletRequest r) {
        return new ErrorEnvelope(new Error(code,code,false,Map.of()),meta(r));
    }
    public static class Failure extends RuntimeException {
        public final int status; public final String code;
        public Failure(int status,String code) { super(code);this.status=status;this.code=code; }
    }
    @RestControllerAdvice
    public static class Advice {
        private final cn.pawday.audit.AuditWriter audit;
        public Advice(cn.pawday.audit.AuditWriter audit){this.audit=audit;}
        @ExceptionHandler(Failure.class)
        ResponseEntity<ErrorEnvelope> failure(Failure f,HttpServletRequest r) {
            if(f.status==401 || f.status==403 || f.status==404) {
                var a=org.springframework.security.core.context.SecurityContextHolder.getContext().getAuthentication();
                var actor=a!=null && a.getPrincipal() instanceof cn.pawday.identity.Actor p?p:null;
                try {audit.write(actor,"security.denied","HTTP_REQUEST",null,Map.of(),Map.of("failure_reason",f.code,"http_status",f.status),r);}
                catch(org.springframework.dao.DataAccessException unavailable) {return persistence(unavailable,r);}
            }
            return ResponseEntity.status(f.status).body(error(f.code,r));
        }
        @ExceptionHandler(cn.pawday.search.OpenSearchClient.Unavailable.class)
        ResponseEntity<ErrorEnvelope> searchUnavailable(cn.pawday.search.OpenSearchClient.Unavailable unavailable,HttpServletRequest r){return ResponseEntity.status(503).body(error(unavailable.code,r));}
        @ExceptionHandler(org.springframework.dao.DataAccessException.class)
        ResponseEntity<ErrorEnvelope> persistence(Exception ignored,HttpServletRequest r){return ResponseEntity.status(503).body(error("PERSISTENCE_UNAVAILABLE",r));}
        @ExceptionHandler({MethodArgumentNotValidException.class,HttpMessageNotReadableException.class})
        ResponseEntity<ErrorEnvelope> invalid(Exception ignored,HttpServletRequest r) {
            return ResponseEntity.badRequest().body(error("VALIDATION_ERROR",r));
        }
    }
}
