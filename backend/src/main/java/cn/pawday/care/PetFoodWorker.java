package cn.pawday.care;
import org.springframework.stereotype.Component;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
@Component @ConditionalOnProperty(name="pawday.care.workers-enabled",havingValue="true",matchIfMissing=true)
public class PetFoodWorker {
 private final PetFoodService service;
 public PetFoodWorker(PetFoodService service){this.service=service;}
 @Scheduled(fixedDelayString="${pawday.care.poll-ms:60000}") public void run(){service.enqueueDue();}
}
