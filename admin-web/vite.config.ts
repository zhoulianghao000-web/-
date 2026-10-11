import {defineConfig} from 'vite';
import vue from '@vitejs/plugin-vue';
const proxy={'/api':{target:process.env.VITE_PAWDAY_PILOT==='true'?'http://127.0.0.1:8086':'http://127.0.0.1:8080',changeOrigin:true}};
export default defineConfig({root:'admin-web',plugins:[vue()],server:{host:'127.0.0.1',port:5174,strictPort:true,proxy},preview:{host:'127.0.0.1',port:4174,strictPort:true,proxy}});
