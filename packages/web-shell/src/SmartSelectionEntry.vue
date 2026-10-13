<script setup lang="ts">
import catPhoto from '../../../consumer-app/flutter/assets/reference/note-cat.jpg';
defineProps<{pilot:boolean}>();
</script>
<template>
  <a class="smart-selection-entry" :href="pilot?'http://127.0.0.1:4175/#/ai':'/consumer-preview/#/ai'" target="_blank" rel="noopener noreferrer" aria-label="智能选品，打开消费者AI选品页">
    <img :src="catPhoto" alt="" /><span><strong>智能选品</strong><small>和你一起慢慢挑好物</small></span><span aria-hidden="true">→</span>
  </a>
</template>
