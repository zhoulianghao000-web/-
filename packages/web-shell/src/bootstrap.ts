import {createApp,watch} from 'vue';
import {createRouter,createWebHistory,type RouteRecordRaw} from 'vue-router';
import {PawdayClient,safeReturnTo,type Realm} from '../../api-client/src';
import {StaffSession} from './auth';
import StaffApp from './StaffApp.vue';
import './theme.css';
export function bootstrap(realm:Exclude<Realm,'consumer'>){
  const apiBase=import.meta.env.VITE_API_BASE_URL??`${location.origin}/api/v1`;
  const client=new PawdayClient(realm,apiBase,fetch,()=>session.clear());
  const session=new StaffSession(client);
  const routes:RouteRecordRaw[]=[
    {path:'/',redirect:'/dashboard'},
    ...['login','dashboard','denied','sessions'].map(page=>({path:`/${page}`,component:{template:'<span />'},meta:{page}})),
    ...(realm==='merchant'?[{path:'/stores',component:{template:'<span />'},meta:{page:'stores',permission:'store.read'}}]:[{path:'/audit',component:{template:'<span />'},meta:{page:'audit',permission:'audit.read'}},{path:'/pet-taxonomy',component:{template:'<span />'},meta:{page:'pet-taxonomy',permission:'pet.taxonomy.read'}}]),
    {path:'/:pathMatch(.*)*',redirect:'/dashboard'},
  ];
  const router=createRouter({history:createWebHistory(),routes});
  router.beforeEach(async to=>{
    if(to.path==='/login')return;
    if(!client.authenticated)return {path:'/login',query:{returnTo:safeReturnTo(to.fullPath)}};
    try{await session.refreshIdentity();}catch{return {path:'/login',query:{returnTo:safeReturnTo(to.fullPath)}};}
    if(!session.can(to.meta.permission as string|undefined))return '/denied';
  });
  watch(()=>session.state.principal,p=>{if(!p&&router.currentRoute.value.path!=='/login')void router.replace({path:'/login',query:{returnTo:safeReturnTo(router.currentRoute.value.fullPath)}});});
  createApp(StaffApp,{realm,session}).use(router).mount('#app');
}
