#!/usr/bin/env bash
# 持续往主库写数据的脚本,用于主从不一致演练
# 用法: nohup ./writer.sh > writer.log 2>&1 &
# 停止: pkill -f writer.sh

PASS='Root@123456'

docker exec -i mysql-master mysql -uroot -p"$PASS" 2>/dev/null <<'SQL'
CREATE DATABASE IF NOT EXISTS drill;
CREATE TABLE IF NOT EXISTS drill.t1(
  id INT AUTO_INCREMENT PRIMARY KEY,
  batch INT,
  val VARCHAR(64),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SQL

echo "$(date '+%F %T') writer 启动,开始持续写入..."

i=1
while true; do
  docker exec mysql-master mysql -uroot -p"$PASS" 2>/dev/null -e \
    "INSERT INTO drill.t1(batch, val) VALUES ($i, 'row-$i');"
  if [ $((i % 50)) -eq 0 ]; then
    echo "$(date '+%F %T') 已写入第 $i 批"
  fi
  i=$((i + 1))
  sleep 0.05   # 约每秒 20 条
done
