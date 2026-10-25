package cn.pawday.integration;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
@Component class IntegrationDeliveryWorker {
 private final IntegrationDeliveryService service;
 IntegrationDeliveryWorker(IntegrationDeliveryService service){this.service=service;}
 @Scheduled(fixedDelayString="${pawday.erp-wms.delivery-delay-ms:5000}") public void recover(){service.recover();}
}
