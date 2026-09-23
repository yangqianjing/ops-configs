# 演练手册:持续写入下的主从不一致 + XtraBackup 重建

演练目标:验证"主库持续写入期间,XtraBackup 热备恢复从库后,复制能自动追平"。

## 准备

把 `drill/` 目录传到服务器 `/data/drill/`(scp 或直接粘贴内容),然后:

```bash
cd /data/drill
chmod +x writer.sh check.sh
```

## 第一步:启动持续写入

```bash
nohup ./writer.sh > writer.log 2>&1 &
```

## 第二步:确认主从同步正常

```bash
./check.sh
# 期望:主库和从库条数一致,两个线程 Yes,Seconds_Behind ≈ 0
```

## 第三步:制造数据不一致(模拟从库被误删数据)

```bash
docker exec -it mysql-slave mysql -uroot -pRoot@123456
```

```sql
SET GLOBAL super_read_only = 0;     -- 临时解锁
DELETE FROM drill.t1 WHERE id > 200;  -- 删掉从库上一批数据
SET GLOBAL super_read_only = 1;     -- 锁回去
```

注意:主库此时还在持续写入,从库复制也还在跑——但删掉的那批行
从库永远没有了,这就是"真不一致"(情况 C)。

## 第四步:确认不一致存在

```bash
./check.sh
# 期望:从库条数明显少于主库,且复制线程还是 Yes(复制没断,但数据已经缺了)
```

## 第五步:主库持续写入中,XtraBackup 热备

```bash
mkdir -p /data/backup

docker run --rm --user root --network data_backend \
  -v data_mysql-master-data:/var/lib/mysql \
  -v /data/backup:/backup \
  percona/percona-xtrabackup:8.0 \
  xtrabackup --backup \
    --host=mysql-master --port=3306 \
    --user=root --password=Root@123456 \
    --target-dir=/backup/full

docker run --rm --user root -v /data/backup:/backup \
  percona/percona-xtrabackup:8.0 \
  xtrabackup --prepare --target-dir=/backup/full
```

备份期间 writer.sh 一直在写,这正是在验证热备能力。

## 第六步:停从库,用备份替换数据目录

```bash
docker compose -f /data/docker-compose.yml stop mysql-slave

docker run --rm \
  -v data_mysql-slave-data:/target \
  -v /data/backup:/backup \
  ubuntu bash -c "
    rm -rf /target/* &&
    cp -a /backup/full/. /target/ &&
    rm -f /target/auto.cnf &&
    chown -R 999:999 /target
  "
```

`rm -f auto.cnf` 不能漏:里面有 server_uuid,不删会和主库撞 UUID。

## 第七步:启动从库,重新挂复制

```bash
docker compose -f /data/docker-compose.yml up -d mysql-slave
docker exec -it mysql-slave mysql -uroot -pRoot@123456
```

```sql
RESET REPLICA ALL;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='mysql-master', SOURCE_PORT=3306,
  SOURCE_USER='repl', SOURCE_PASSWORD='Repl@123456',
  SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1;
START REPLICA;
SET PERSIST super_read_only = 1;   -- 新数据目录,记得补上
```

GTID 位点已随备份文件带过来,AUTO_POSITION 会自动从断点续传——
备份结束到此刻主库新写入的数据,全部靠复制追回来。

## 第八步:观察追平过程

```bash
watch -n1 ./check.sh
# 期望:Seconds_Behind 从大到小归 0,主从条数逐渐一致
```

## 收尾:停止写入,清理演练数据

```bash
pkill -f writer.sh
docker exec mysql-master mysql -uroot -pRoot@123456 -e "DROP DATABASE drill;"
./check.sh   # 从库应同步删掉 drill 库
```

## 演练中要记住的三个要点

1. 备份过程中主库从没停写——XtraBackup 靠 redo log 保证备份一致性
2. 恢复出来的从库是"备份结束那一刻"的主库,之后缺的靠复制追
3. 从库永远以主库为准,不一致就重建,这是成本最低的修复
