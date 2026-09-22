-- 首次初始化时自动创建复制账号(仅数据卷为空时执行一次)
CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED BY 'Repl@123456';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;