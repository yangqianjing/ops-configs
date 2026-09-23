#!/usr/bin/env bash
# 对比主从数据量,观察一致性
# 用法: ./check.sh        单次对比
#       watch -n1 ./check.sh   持续观察

PASS='Root@123456'

M=$(docker exec mysql-master mysql -uroot -p"$PASS" -N 2>/dev/null \
    -e "SELECT COUNT(*) FROM drill.t1;")
S=$(docker exec mysql-slave mysql -uroot -p"$PASS" -N 2>/dev/null \
    -e "SELECT COUNT(*) FROM drill.t1;")

echo "主库: ${M:-?} 条 | 从库: ${S:-?} 条 | 差异: $(( ${M:-0} - ${S:-0} )) 条"
docker exec mysql-slave mysql -uroot -p"$PASS" -N 2>/dev/null -e \
  "SHOW REPLICA STATUS\G" | grep -E "Replica_(IO|SQL)_Running|Seconds_Behind"
