# Verification Module Dependency Graph

## Module Declarations

| VM | Name | Weight | Dependencies |
|----|------|--------|-------------|
| VM-03 | 用户管理 | 10 | none (foundational) |
| VM-01 | 安装协议 | 9 | VM-03 |
| VM-04 | 分流管理 | 7 | VM-01 |
| VM-06 | 订阅管理 | 6 | VM-01, VM-03 |
| VM-05 | 协议管理 | 5 | VM-01 |
| VM-02 | 卸载协议 | 3 | VM-01 |
| VM-07 | 查看配置 | 2 | VM-01 |
| VM-08 | 运行日志 | 2 | VM-01 |
| VM-09 | 内核管理 | 1 | none |
| VM-10 | 网络管理 | 1 | none |
| VM-11 | 脚本更新 | 1 | none |
| VM-12 | 卸载服务 | 0 | none (destructive, always last) |

## Dependency Graph

```
VM-03 (weight=10) ──> VM-01 (weight=9)
                        ├──> VM-05 (weight=5)
                        ├──> VM-04 (weight=7)
                        ├──> VM-06 (weight=6) <── VM-03
                        ├──> VM-07 (weight=2)
                        ├──> VM-08 (weight=2)
                        └──> VM-02 (weight=3)
VM-09 (weight=1)  — independent
VM-10 (weight=1)  — independent
VM-11 (weight=1)  — independent
VM-12 (weight=0)  — destructive, always last, optional
```

Arrow direction: `A ──> B` means "A must complete before B can run" (A is a dependency of B).

## Direct Dependents Lookup (for Tier 2)

| Module | Direct Dependents |
|--------|------------------|
| VM-03 | VM-01, VM-06 |
| VM-01 | VM-02, VM-04, VM-05, VM-06, VM-07, VM-08 |
| VM-02 | none |
| VM-04 | none |
| VM-05 | none |
| VM-06 | none |
| VM-07 | none |
| VM-08 | none |
| VM-09 | none |
| VM-10 | none |
| VM-11 | none |
| VM-12 | none |

## Topological Sort (Tier 3 Execution Order)

Sorted by: dependencies first, then descending weight.

```
1.  VM-03  用户管理       (weight=10, deps: none)
2.  VM-01  安装协议       (weight=9,  deps: VM-03)
3.  VM-05  协议管理       (weight=5,  deps: VM-01)
4.  VM-04  分流管理       (weight=7,  deps: VM-01)
5.  VM-06  订阅管理       (weight=6,  deps: VM-01, VM-03)
6.  VM-07  查看配置       (weight=2,  deps: VM-01)
7.  VM-08  运行日志       (weight=2,  deps: VM-01)
8.  VM-02  卸载协议       (weight=3,  deps: VM-01)
9.  VM-09  内核管理       (weight=1,  deps: none)
10. VM-10  网络管理       (weight=1,  deps: none)
11. VM-11  脚本更新       (weight=1,  deps: none)
12. VM-12  卸载服务       (weight=0,  deps: none) — OPTIONAL, destructive
```

## Weight Rationale

- **Higher weight** = more downstream modules depend on its state being correct
- **VM-03 (10)**: foundational user data; VM-01 and VM-06 depend on it
- **VM-01 (9)**: protocol installation is prerequisite for 6 other modules
- **VM-04 (7)**: routing rules are high-value and complex
- **VM-06 (6)**: subscription depends on both users and protocols
- **VM-05 (5)**: service management is operationally important
- **VM-02 (3)**: uninstall is destructive within the protocol scope, run after verification
- **VM-07/08 (2)**: read-only observation, low risk
- **VM-09/10/11 (1)**: independent system operations
- **VM-12 (0)**: full uninstall, never auto-included
