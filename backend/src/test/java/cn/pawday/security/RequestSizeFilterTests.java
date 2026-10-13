package cn.pawday.security;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;
import static org.junit.jupiter.api.Assertions.*;

class RequestSizeFilterTests {
    @Test void declaredOversizeIsRejectedBeforeParsing() throws Exception {
        var request=new MockHttpServletRequest("POST","/api/v1/admin/auth/login");request.setContent(new byte[RequestSizeFilter.MAX_JSON_BYTES+1]);
        var response=new MockHttpServletResponse();new RequestSizeFilter().doFilter(request,response,(r,s)->fail("oversize reached controller"));
        assertEquals(413,response.getStatus());assertTrue(response.getContentAsString().contains("REQUEST_BODY_TOO_LARGE"));
    }
    @Test void unknownLengthCannotBypassLimit() throws Exception {
        var request=new MockHttpServletRequest("POST","/api/v1/consumer/purchase-requests"){
            @Override public long getContentLengthLong(){return -1;}
            @Override public int getContentLength(){return -1;}
        };request.setContent(new byte[RequestSizeFilter.MAX_JSON_BYTES+1]);
        var response=new MockHttpServletResponse();new RequestSizeFilter().doFilter(request,response,(r,s)->fail("unbounded stream reached controller"));assertEquals(413,response.getStatus());
    }
    @Test void ordinaryJsonRetainsExactBodyAndRequestIdentity() throws Exception {
        var request=new MockHttpServletRequest("POST","/api/v1/admin/auth/login");byte[] body="{\"login_name\":\"TEST\"}".getBytes(StandardCharsets.UTF_8);request.setContent(body);request.setAttribute("request_id","TEST_REQUEST");
        var reached=new AtomicBoolean();new RequestSizeFilter().doFilter(request,new MockHttpServletResponse(),(r,s)->{reached.set(true);assertArrayEquals(body,r.getInputStream().readAllBytes());assertEquals("TEST_REQUEST",r.getAttribute("request_id"));});assertTrue(reached.get());
    }
    @Test void boundedCatalogImportLimitIsStillSupported() throws Exception {
        var request=new MockHttpServletRequest("POST","/api/v1/admin/catalog/imports");request.setContent(new byte[2_800_100]);
        new RequestSizeFilter().doFilter(request,new MockHttpServletResponse(),(r,s)->assertEquals(2_800_100,r.getInputStream().readAllBytes().length));
    }
    @Test void binaryUploadRemainsStreamingUnderMediaValidation() throws Exception {
        var request=new MockHttpServletRequest("PUT","/api/v1/media/00000000-0000-0000-0000-000000000001/content");request.setContent(new byte[4*1024*1024]);
        new RequestSizeFilter().doFilter(request,new MockHttpServletResponse(),(r,s)->assertSame(request,r));
    }
}
