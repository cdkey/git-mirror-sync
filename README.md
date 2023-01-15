# git-mirror-sync

### 目的

在内外网隔离的环境，以离线方式同步外网git仓库，首次全量同步，后续增量同步

假设外网机器为 A，内网机器为 B，以 linux-stable.git 仓库为例说明使用过程

### 全量同步

- 在外网 A 机器创建全量 bundle 文件
  - 全量克隆/更新需要同步的 git 仓库

    ```bash
    git clone https://mirrors.tuna.tsinghua.edu.cn/git/linux-stable.git
    cd linux-stable
    ```

  - 【可选】更新远程分支到本地

    ```bash
    git remote update origin
    ```

  - 创建全量 bundle 文件 (打包所有远程分支及标签到 stable.bundle 文件)

    ```bash
    git-mirror-sync.sh full stable.bundle
    ```

  - 【可选】查看或验证 bundle 文件

    ```bash
    git bundle list-heads stable.bundle
    git bundle verify stable.bundle
    ```

- 将 stable.bundle 拷贝至内网 B 机器
- 在内网 B 机器还原 git 仓库
  - 从 stable.bundle 文件中克隆 git 仓库

    ```bash
    mkdir linux-stable
    git init
    git remote add --mirror=fetch origin /path/of/stable.bundle
    ```

  - 检查git仓库配置，origin配置类似如下 (**保持 origin 跟踪 stable.bundle 文件**)

    ```
    [remote "origin"]
        url = /path/of/stable.bundle
        fetch = +refs/*:refs/*
    ```

  - 更新本地镜像仓库

    ```bash
    git remote update origin
    ```

  - 查看远程分支`git branch -r`，应该会显示所有远程分支

- 将内网 B 机器的 git 仓库推送至内网 git 服务器
  - 内网 git 服务器上创建镜像仓库
  - B 机器添加镜像仓库源，假设名叫 gogs，与 origin 区分

    ```bash
    git remote add gogs git@my.gogs:mirror/linux-stable.git
    ```

  - 设置 gogs 的推送规则 (推送origin的分支到gogs, 推送tags到gogs)
    **这是一个优化步骤，因为 linux-stable 的分支很多，常规操作需要将 origin 的远程分支全部检出成为>本地分支再推送至 mirror，不够优雅，经过研究后可以跳过本地分支步骤**

    ```bash
    git config remote.gogs.push "refs/remotes/origin/*:refs/heads/*"
    git config --add remote.gogs.push "refs/tags/*:refs/tags/*"
    ```

  - 检查 gogs 的配置，类似如下

    ```
    [remote "gogs"]
        url = git@my.gogs:mirror/linux-stable.git
        push = refs/remotes/origin/*:refs/heads/*
        push = refs/tags/*:refs/tags/*
    ```

  - 将 B 的 origin 远程分支和标签推送至 mirror

    ```bash
    git push gogs
    ```

完成了首次全量镜像导入后，之后对外网仓库更新就可以采用增量同步的方式进行跟进

### 增量同步

- 在外网 A 主机 git 仓库记录前一次全量/增量同步的位置 (**特别注意: 一定要在A主机 git 仓库更新前标记位置**)
  该操作将原始仓库的branch和tag信息以内部tag的方式保存到`last-sync/*`

  ```bash
  git-mirror-sync.sh tag
  ```

  可以通过 `git tag -l | grep last-sync` 查看此记录

- 更新外网 A 主机的 git 仓库

  ```bash
  git remote update origin
  git fetch --tags -f origin
  ```

  git 输出信息表明哪些远程分支有更新，以及新增了哪些 tag

- 创建增量 bundle 文件

  使用所有有更新的远程分支增量部分和新增的 tag 创建 bundle 文件 (见 git-mirror-sync.sh)

  ```bash
  git-mirror-sync inc stable.bundle
  ```

- 将 stable.bundle 拷贝至内网 B 机器

- 在内网 B 机器进行增量更新
  - 用新的增量 stable.bundle 替换之前的全量/增量 bundle 文件 (`git remote -v`看到的路径位置)
  - 从新的增量 stable.bundle 中拉取更新数据

    ```bash
    git remote update origin
    ```

    经过此步骤操作后，更新增量数据已落入本地（未检出到本地分支，但 refs/remotes/origin/* 已可以引用到）

  - 将增量更新推入镜像仓库

    ```bash
    git push gogs
    ```

### 导入导出同步点

使用场景举例

- 原外网 A 主机 git 仓库被破坏，丢失了之前的同步位置信息
- 在外网 A' 主机新建了 git 仓库，后续期望增量同步从 A' 仓库生成

操作方法

1. 在内网 B 主机导出已同步的位置信息

  ```bash
  git-mirror-sync.sh export pos.txt
  ```

2. 拷贝pos.txt或复制内容

3. 在外网 A 或 A' 仓库导入同步位置信息

  ```bash
  git-mirror-sync.sh import pos.txt
  ```

完成后即可像之前一样继续增量同步仓库数据

