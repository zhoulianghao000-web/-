package cn.pawday.storage;
import cn.pawday.common.Api.Failure;
import java.nio.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import static org.junit.jupiter.api.Assertions.*;
class VideoContentValidatorTests {
 @TempDir Path dir;
 byte[] fixture()throws Exception{try(var in=getClass().getResourceAsStream("/review-video.base64")){return Base64.getDecoder().decode(new String(in.readAllBytes(),StandardCharsets.US_ASCII).strip());}}
 Path file(byte[] bytes)throws Exception{return Files.write(dir.resolve(UUID.randomUUID()+".mp4"),bytes);}
 int atom(byte[] data,String name){int found=new String(data,StandardCharsets.ISO_8859_1).lastIndexOf(name);assertTrue(found>0);return found;}
 @Test void rejectsTruncatedAndForgedContainerLengths()throws Exception{byte[] b=fixture();assertThrows(Failure.class,()->VideoContentValidator.validate(file(Arrays.copyOf(b,40))));ByteBuffer.wrap(b).putInt(Integer.MAX_VALUE);assertThrows(Failure.class,()->VideoContentValidator.validate(file(b)));}
 @Test void rejectsOverlongVideoEvenWithValidFileHash()throws Exception{byte[] b=fixture();int mvhd=atom(b,"mvhd");long scale=Integer.toUnsignedLong(ByteBuffer.wrap(b,mvhd+16,4).getInt());ByteBuffer.wrap(b,mvhd+20,4).putInt((int)(scale*121));var failure=assertThrows(Failure.class,()->VideoContentValidator.validate(file(b)));assertEquals("UPLOAD_VIDEO_DURATION",failure.code);}
 @Test void rejectsExternalMediaReferences()throws Exception{byte[] b=fixture();ByteBuffer.wrap(b,atom(b,"url ")+4,4).putInt(0);assertThrows(Failure.class,()->VideoContentValidator.validate(file(b)));}
 @Test void rejectsUnsupportedVideoCodec()throws Exception{byte[] b=fixture();int pos=atom(b,"avc1");System.arraycopy("hvc1".getBytes(StandardCharsets.US_ASCII),0,b,pos,4);var failure=assertThrows(Failure.class,()->VideoContentValidator.validate(file(b)));assertEquals("UPLOAD_VIDEO_CODEC",failure.code);}
 @Test void rejectsInvalidCodecConfiguration()throws Exception{byte[] b=fixture();b[atom(b,"avcC")+4]=0;assertThrows(Failure.class,()->VideoContentValidator.validate(file(b)));}
}
