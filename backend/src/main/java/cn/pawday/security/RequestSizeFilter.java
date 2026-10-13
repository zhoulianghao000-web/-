package cn.pawday.security;

import cn.pawday.common.Api;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.Set;
import org.springframework.web.filter.OncePerRequestFilter;
import tools.jackson.databind.json.JsonMapper;

/** Bound JSON before deserialization, including HTTP bodies with no declared length. */
public final class RequestSizeFilter extends OncePerRequestFilter {
    static final int MAX_JSON_BYTES=3*1024*1024;
    private final JsonMapper json=JsonMapper.builder().build();
    @Override protected void doFilterInternal(HttpServletRequest request,HttpServletResponse response,FilterChain chain) throws IOException,ServletException {
        String path=request.getRequestURI();
        // Binary uploads are streamed and independently size/hash/MIME checked by MediaService.
        if(!path.startsWith("/api/v1/")||!Set.of("POST","PUT","PATCH").contains(request.getMethod())||
            request.getMethod().equals("PUT")&&path.matches("/api/v1/media/[0-9a-fA-F-]{36}/content")) {
            chain.doFilter(request,response);return;
        }
        if(request.getContentLengthLong()>MAX_JSON_BYTES){reject(request,response);return;}
        byte[] body=request.getInputStream().readNBytes(MAX_JSON_BYTES+1);
        if(body.length>MAX_JSON_BYTES){reject(request,response);return;}
        chain.doFilter(new HttpServletRequestWrapper(request){
            @Override public int getContentLength(){return body.length;}
            @Override public long getContentLengthLong(){return body.length;}
            @Override public ServletInputStream getInputStream(){
                var input=new ByteArrayInputStream(body);
                return new ServletInputStream(){
                    @Override public int read(){return input.read();}
                    @Override public int read(byte[] b,int off,int len){return input.read(b,off,len);}
                    @Override public boolean isFinished(){return input.available()==0;}
                    @Override public boolean isReady(){return true;}
                    @Override public void setReadListener(ReadListener listener){throw new IllegalStateException("Synchronous bounded request body");}
                };
            }
            @Override public BufferedReader getReader(){return new BufferedReader(new InputStreamReader(getInputStream(),StandardCharsets.UTF_8));}
        },response);
    }
    private void reject(HttpServletRequest request,HttpServletResponse response) throws IOException {
        response.setStatus(413);response.setContentType("application/json");
        response.getWriter().write(json.writeValueAsString(Api.error("REQUEST_BODY_TOO_LARGE",request)));
    }
}
