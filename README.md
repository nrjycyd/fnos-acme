# fnOS-acme

飞牛私有云 HTTPS+SSL 泛域名证书部署脚本

### 实现效果

自动申请泛域名证书并替换 fnOS 服务器默认证书。

### 文件说明

- `config`: 配置文件，设置域名、DNS 服务商、CA 证书环境等；
- `fnos-acme.sh`: 证书申请脚本，需要手动使用 `sudo` 命令执行或添加到 cron 作业；
- `fnos-ser.sh`: 证书替换脚本，**由 `fnos-acme.sh` 自动调用，无需用户手动配置或执行**；

> [!NOTE]
>
> 飞牛私有云 cron 服务配置：`sudo crontab -e`
>
> 配置示范：`0 3 1 * * /vol1/1000/Other/acme-ssl/fnos-acme.sh`


### 具体操作

1.  将 `config`、`fnos-acme.sh`、`fnos-ser.sh` 下载到您希望存放脚本的目录，例如 `/vol1/1000/Other/acme-ssl/`；

2.  配置 `config` 文件；

3.  添加脚本执行权限：

    ```bash
    sudo chmod +x /vol1/1000/Other/acme-ssl/fnos-acme.sh
    sudo chmod +x /vol1/1000/Other/acme-ssl/fnos-ser.sh
    ```

4.  执行 `fnos-acme.sh` 脚本：

    ```bash
    sudo /vol1/1000/Other/acme-ssl/fnos-acme.sh
    ```

### 注意事项

-   请确认下载到本地的文件具有执行权限 (`chmod +x` 或 `sudo chmod +x`)；
-   `fnos-ser.sh` 脚本用于将成功申请的证书替换到服务器中，**此过程需要管理员权限。因此，执行 `fnos-acme.sh` 脚本时，请务必使用 `sudo` 命令或在管理员账户下运行，以确保证书申请和替换都能成功完成。**
