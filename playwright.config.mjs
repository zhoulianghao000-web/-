import {defineConfig} from '@playwright/test';
export default defineConfig({
  testDir:'./e2e',timeout:30000,fullyParallel:true,
  reporter:[['list'],['html',{open:'never'}]],
  use:{browserName:'chromium',trace:'retain-on-failure',screenshot:'only-on-failure'},
  webServer:[
    {command:'node node_modules/vite/bin/vite.js --config merchant-web/vite.config.ts',url:'http://127.0.0.1:5173',reuseExistingServer:!process.env.CI},
    {command:'node node_modules/vite/bin/vite.js --config admin-web/vite.config.ts',url:'http://127.0.0.1:5174',reuseExistingServer:!process.env.CI},
  ],
});
