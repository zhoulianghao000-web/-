async function health(){
  const el=document.getElementById('health');
  try{const status=await(await fetch('/desktop-status',{cache:'no-store'})).json();el.textContent=status.healthy?'● 本机服务健康 · PostgreSQL / Redis / RabbitMQ / OpenSearch 已连接':'○ 本机服务尚未就绪，请查看项目目录 .pilot 中本轮的日志。';}
  catch{el.textContent='○ 无法连接本机启动入口，请重新运行桌面快捷方式。';}
}
void health();setInterval(health,15000);
