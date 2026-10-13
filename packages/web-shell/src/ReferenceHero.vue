<script setup lang="ts">
import heroPhoto from '../../../consumer-app/flutter/assets/reference/hero-dogs.jpg';
defineProps<{heading:string;copy:string;to:string;action:string}>();
</script>
<template>
  <div class="reference-hero">
    <div class="reference-hero-copy"><p class="eyebrow">MADE FOR LITTLE COMPANIONS</p><h1>{{ heading }}</h1><p>{{ copy }}</p><RouterLink class="btn-primary" :to="to">{{ action }} <span aria-hidden="true">→</span></RouterLink></div>
    <div class="reference-hero-visual"><img class="reference-hero-photo" :src="heroPhoto" alt="一起散步的狗狗" /><div class="hero-sticker"><b>好奇心</b><span>每天都要有</span></div></div>
  </div>
</template>
