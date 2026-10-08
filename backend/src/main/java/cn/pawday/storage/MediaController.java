package cn.pawday.storage;

import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.io.IOException;
import java.util.UUID;
import org.springframework.core.io.InputStreamResource;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/media")
public class MediaController {
    public record GrantRequest(@NotBlank String scope,@NotBlank String mime,@NotNull Long size_bytes,@NotBlank String sha256,UUID store_id) {}
    private final MediaService service;private final AccessGuard guard;
    public MediaController(MediaService service,AccessGuard guard){this.service=service;this.guard=guard;}
    @PostMapping("/upload-grants") @ResponseStatus(HttpStatus.CREATED)
    Api.Envelope<MediaService.Grant> grant(@Valid @RequestBody GrantRequest body,HttpServletRequest request){return Api.ok(service.grant(body.scope(),body.mime(),body.size_bytes(),body.sha256(),body.store_id(),request),request);}
    @PutMapping("/{asset_id}/content")
    Api.Envelope<MediaService.Asset> upload(@PathVariable String asset_id,@RequestHeader(value="X-Upload-Token",required=false) String token,HttpServletRequest request) throws IOException {
        if(request.getHeader("Content-Encoding")!=null&&!request.getHeader("Content-Encoding").equals("identity"))throw new Api.Failure(400,"UPLOAD_ENCODING_NOT_ALLOWED");
        return Api.ok(service.upload(guard.id(asset_id),token,request.getContentType(),request.getContentLengthLong(),request.getInputStream(),request),request);
    }
    @GetMapping("/{asset_id}")
    Api.Envelope<MediaService.Asset> metadata(@PathVariable String asset_id,HttpServletRequest request){return Api.ok(service.metadata(guard.id(asset_id)),request);}
    @GetMapping("/{asset_id}/content")
    ResponseEntity<InputStreamResource> content(@PathVariable String asset_id){var content=service.content(guard.id(asset_id));return ResponseEntity.ok().contentType(MediaType.parseMediaType(content.asset().mime())).contentLength(content.asset().size_bytes()).header("X-Content-Type-Options","nosniff").header("Cache-Control","private, no-store").header("Content-Disposition","inline; filename=\""+content.asset().asset_id()+(content.asset().mime().equals("video/mp4")?".mp4":content.asset().mime().equals("image/png")?".png":".jpg")+"\"").body(new InputStreamResource(content.input()));}
    @DeleteMapping("/{asset_id}") @ResponseStatus(HttpStatus.ACCEPTED)
    Api.Envelope<MediaService.Asset> delete(@PathVariable String asset_id,HttpServletRequest request){return Api.ok(service.delete(guard.id(asset_id),request),request);}
}
