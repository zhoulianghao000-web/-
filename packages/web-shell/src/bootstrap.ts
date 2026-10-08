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
    ...(realm==='admin'?[{path:'/shipping',component:{template:'<span />'},meta:{page:'shipping',permission:'pricing.shipping.manage'}}]:[]),
    {path:'/orders',component:{template:'<span />'},meta:{page:'orders',permission:realm==='merchant'?'order.read':'order.admin.read'}},
    ...(realm==='admin'?[{path:'/order-policies',component:{template:'<span />'},meta:{page:'order-policies',permission:'order.policy.manage'}}]:[]),
    ...(realm==='admin'?[{path:'/settlements',component:{template:'<span />'},meta:{page:'settlements',permission:'settlement.read'}},{path:'/finance-policies',component:{template:'<span />'},meta:{page:'finance-policies',permission:'settlement.policy.manage'}},{path:'/membership',component:{template:'<span />'},meta:{page:'membership',permission:'points.read'}}]:[{path:'/finance',component:{template:'<span />'},meta:{page:'finance',permission:'ledger.read'}}]),
    {path:'/reviews',component:{template:'<span />'},meta:{page:'reviews',permission:realm==='merchant'?'review.merchant.read':'review.read'}},
    ...(realm==='admin'?[{path:'/content',component:{template:'<span />'},meta:{page:'content',permission:'content.read'}}]:[]),
    {path:'/offers',component:{template:'<span />'},meta:{page:'offers',permission:realm==='merchant'?'offer.read':'offer.admin.read'}},
    {path:'/catalog',component:{template:'<span />'},meta:{page:'catalog',permission:'catalog.standard.read'}},
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
