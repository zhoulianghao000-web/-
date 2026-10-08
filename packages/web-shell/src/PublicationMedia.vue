<script setup lang="ts">
import {ref,watch,onUnmounted} from 'vue';
import {PawdayClient,type components} from '../../api-client/src';
const props=defineProps<{client:PawdayClient;media:components['schemas']['PublicationMedia']}>();
const src=ref(''),error=ref('');let generation=0;
function clear(){generation++;if(src.value)URL.revokeObjectURL(src.value);src.value='';error.value='';}
watch(()=>[props.media.content_url,props.media.available],async()=>{clear();if(!props.media.available)return;const own=generation;
 try{const blob=await props.client.publicationMedia(props.media.content_url);if(own===generation)src.value=URL.createObjectURL(blob);}catch{if(own===generation)error.value='资源暂时不可读取';}
},{immediate:true});onUnmounted(clear);
</script>
<template><figure><video v-if="src&&media.mime==='video/mp4'" :src="src" controls preload="metadata" playsinline aria-label="评价视频" /><img v-else-if="src" :src="src" alt="发布内容附件" loading="lazy" /><figcaption v-if="error||!media.available">{{ error||'资源不可用' }}</figcaption></figure></template>
<style scoped>img,video{max-width:100%;max-height:320px;border-radius:12px}figure{margin:12px 0}</style>
