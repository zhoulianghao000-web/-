package cn.pawday.publishing;
import org.springframework.core.io.InputStreamResource;
import org.springframework.http.*;
public final class PublishingMedia {
 private PublishingMedia(){}
 public static ResponseEntity<InputStreamResource> response(PublishingSupport.Content c){return ResponseEntity.ok().contentType(MediaType.parseMediaType(c.mime())).contentLength(c.size()).header("X-Content-Type-Options","nosniff").header("Cache-Control","private, no-store").header("Content-Disposition","inline").body(new InputStreamResource(c.stream()));}
}
