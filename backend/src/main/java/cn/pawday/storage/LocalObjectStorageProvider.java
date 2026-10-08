package cn.pawday.storage;

import cn.pawday.common.Api.Failure;
import java.awt.image.BufferedImage;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.channels.Channels;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import javax.imageio.ImageIO;

/** Real filesystem adapter. The configured directory must be owned by the server account. */
public class LocalObjectStorageProvider implements ObjectStorageProvider {
    private final Path root;
    public LocalObjectStorageProvider(Path directory) {
        root=directory.toAbsolutePath().normalize();
        try {rejectLinks(root);Files.createDirectories(root);rejectLinks(root);safeDirectory(root.resolve("media"));safeDirectory(root.resolve(".incoming"));}
        catch(IOException e){throw unavailable();}
    }
    @Override public int reapAbandonedUploads(java.time.Instant olderThan) {
        int removed=0,visited=0;
        try {Path incoming=root.resolve(".incoming");rejectLinks(incoming);if(!Files.isDirectory(incoming,LinkOption.NOFOLLOW_LINKS))throw unavailable();
            try(var files=Files.newDirectoryStream(incoming,"upload-*.tmp")){for(Path file:files){if(++visited>256)break;rejectLinks(file);
                if(Files.isRegularFile(file,LinkOption.NOFOLLOW_LINKS)&&Files.getLastModifiedTime(file,LinkOption.NOFOLLOW_LINKS).toInstant().isBefore(olderThan)){
                    try{if(Files.deleteIfExists(file))removed++;}catch(IOException busy){/* An open Windows upload file is retried on a later pass. */}
                }
            }}return removed;
        }catch(Failure f){throw f;}catch(IOException unavailable){throw unavailable();}
    }
    @Override public String providerId(){return "local";}
    private Failure unavailable(){return new Failure(503,"OBJECT_STORAGE_UNAVAILABLE");}
    private void rejectLinks(Path path) throws IOException {
        for(Path cursor=path;cursor!=null;cursor=cursor.getParent()) {
            if(Files.exists(cursor,LinkOption.NOFOLLOW_LINKS)) {
                if(Files.isSymbolicLink(cursor)||!cursor.toRealPath().equals(cursor.toAbsolutePath().normalize()))throw new IOException("link path refused");
            }
        }
    }
    private void safeDirectory(Path path) throws IOException {rejectLinks(path);Files.createDirectories(path);rejectLinks(path);if(!Files.isDirectory(path,LinkOption.NOFOLLOW_LINKS))throw new IOException("not a directory");}
    private Path path(String key) throws IOException {
        if(key==null||!key.matches("media/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\.(png|jpg|mp4)"))throw new Failure(400,"INVALID_OBJECT_KEY");
        if(!Files.isDirectory(root.resolve("media"),LinkOption.NOFOLLOW_LINKS))throw new IOException("object directory unavailable");
        Path target=root.resolve(key).normalize();rejectLinks(target);if(!target.startsWith(root))throw new Failure(400,"INVALID_OBJECT_KEY");return target;
    }
    @Override public Metadata put(Put request,InputStream content) {
        Path staging=null;
        try {
            Path target=path(request.objectKey());safeDirectory(root.resolve(".incoming"));
            staging=Files.createTempFile(root.resolve(".incoming"),"upload-",".tmp");
            MessageDigest digest=MessageDigest.getInstance("SHA-256");long size=0;
            try(var channel=Files.newByteChannel(staging,Set.of(StandardOpenOption.WRITE,LinkOption.NOFOLLOW_LINKS));var out=Channels.newOutputStream(channel)) {
                byte[] buffer=new byte[16384];int read;
                while((read=content.read(buffer))!=-1) {
                    size+=read;if(size>request.maxBytes()||size>request.sizeBytes())throw new Failure(413,"UPLOAD_TOO_LARGE");
                    digest.update(buffer,0,read);out.write(buffer,0,read);
                }
            }
            if(size!=request.sizeBytes())throw new Failure(400,"UPLOAD_SIZE_MISMATCH");
            String hash=HexFormat.of().formatHex(digest.digest());if(!hash.equals(request.sha256()))throw new Failure(400,"UPLOAD_HASH_MISMATCH");
            if(request.mime().equals("video/mp4"))VideoContentValidator.validate(staging);else validateImage(staging,request.mime());
            // Immutable key: credentials cannot replace existing content. No cloud-dependent overwrite behavior.
            rejectLinks(target);Files.move(staging,target);staging=null;
            return new Metadata(request.objectKey(),request.mime(),size,hash);
        } catch(Failure failure){throw failure;}
        catch(FileAlreadyExistsException exists){throw new Failure(409,"OBJECT_ALREADY_EXISTS");}
        catch(Exception ignored){throw unavailable();}
        finally {if(staging!=null)try {Files.deleteIfExists(staging);}catch(IOException ignored){}}
    }
    private void validateImage(Path file,String mime) throws IOException {
        byte[] magic=new byte[8];try(var in=Files.newInputStream(file,LinkOption.NOFOLLOW_LINKS)){if(in.read(magic)!=8)throw new Failure(400,"UPLOAD_INVALID_CONTENT");}
        boolean png=Arrays.equals(magic,new byte[]{(byte)137,80,78,71,13,10,26,10});
        boolean jpeg=(magic[0]&255)==255&&(magic[1]&255)==216&&(magic[2]&255)==255;
        if(!(mime.equals("image/png")&&png||mime.equals("image/jpeg")&&jpeg))throw new Failure(400,"UPLOAD_MIME_MISMATCH");
        try(var imageInput=ImageIO.createImageInputStream(file.toFile())) {
            var readers=ImageIO.getImageReaders(imageInput);if(!readers.hasNext())throw new Failure(400,"UPLOAD_INVALID_CONTENT");
            var reader=readers.next();try {reader.setInput(imageInput,true,true);long width=reader.getWidth(0),height=reader.getHeight(0);
                if(width<1||height<1||width>8192||height>8192||width*height>16000000)throw new Failure(400,"UPLOAD_IMAGE_DIMENSIONS");
                BufferedImage decoded=reader.read(0);if(decoded==null)throw new Failure(400,"UPLOAD_INVALID_CONTENT");decoded.flush();
            } finally {reader.dispose();}
        } catch(Failure f){throw f;}catch(Exception invalid){throw new Failure(400,"UPLOAD_INVALID_CONTENT");}
    }
    @Override public Optional<Metadata> metadata(String key) {
        try {Path p=path(key);if(!Files.exists(p,LinkOption.NOFOLLOW_LINKS))return Optional.empty();if(!Files.isRegularFile(p,LinkOption.NOFOLLOW_LINKS))throw unavailable();
            long size=Files.size(p);MessageDigest digest=MessageDigest.getInstance("SHA-256");try(var in=Files.newInputStream(p,LinkOption.NOFOLLOW_LINKS)) {byte[] b=new byte[16384];int n;while((n=in.read(b))!=-1)digest.update(b,0,n);}
            return Optional.of(new Metadata(key,key.endsWith(".mp4")?"video/mp4":key.endsWith(".png")?"image/png":"image/jpeg",size,HexFormat.of().formatHex(digest.digest())));
        }catch(Failure f){throw f;}catch(Exception ignored){throw unavailable();}
    }
    @Override public InputStream read(String key) {
        try {Path p=path(key);if(!Files.isRegularFile(p,LinkOption.NOFOLLOW_LINKS))throw new Failure(404,"MEDIA_CONTENT_NOT_FOUND");return Files.newInputStream(p,LinkOption.NOFOLLOW_LINKS);}
        catch(Failure f){throw f;}catch(IOException ignored){throw unavailable();}
    }
    @Override public void delete(String key) {try {Files.deleteIfExists(path(key));}catch(Failure f){throw f;}catch(IOException ignored){throw unavailable();}}
}
