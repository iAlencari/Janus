<p align="center"><img src="instalador/janus-icone.png" width="96" alt="Janus"></p>

<h1 align="center">Janus</h1>
<p align="center"><b>Ajustes do Windows explicados e reversíveis.</b><br>
Português · <a href="#english">English</a> · <a href="#español">Español</a> · <a href="#中文">中文</a></p>

> **Beta.** O Janus ainda está em construção. A primeira versão estável é a 0.1 BETA.

O Janus mostra o **estado real** de cada configuração do Windows, explica cada mudança em linguagem simples e deixa você **desfazer tudo**.

## O que ele faz

| Aba | Para quê |
|---|---|
| **Visão geral** | Ajustes ativos, selo de autenticidade, segurança e hardware ao vivo (processador, memória, placa de vídeo, disco, SSD e rede) com barras de 0 a 100%. |
| **Sugestões** | Ajustes recomendados para o seu PC. Aplique ou descarte (só até fechar o app ou para sempre). |
| **Automação** | Lê o hardware e decide sozinho o que vale aplicar, explicando o motivo de cada decisão. |
| **Otimizações** (modo Simplificado) ou **Mouse, teclado e controle · Gráficos e jogos · Rede e energia · Privacidade · Interface** (modo Por categoria) | Ajustes em botões liga e desliga, com "Não recomendado se..." em cada um. Ordem por prioridade, nome ou categoria, em grade ou detalhado. |
| **Rede / Internet e DNS** | DNS seguro (Quad9, Cloudflare, Google, AdGuard, OpenDNS, Control D, NextDNS, UltraDNS) com teste de resposta, e teste de velocidade de cada conexão (cabo e Wi-Fi, sem desconectar nada). |
| **Jogos** | Encontra os jogos instalados e monta a pergunta da configuração ideal para a IA que você escolher (Claude, ChatGPT, Gemini, Grok ou DeepSeek). |
| **Segurança** | Verificações. Firewall e integridade de memória só são desligados se você pedir, com avisos, timer e lembretes. O UAC, nunca. |
| **Manutenção** | Ponto de restauração, verificação do Defender, limpeza de temporários e reinício do Explorer. |
| **Mudanças aplicadas** | Tudo o que está mudado agora, com "Desfazer" em cada item ou em todos de uma vez. |
| **Engrenagem** ⚙ | Idioma, tema (escuro, claro ou do Windows), visualização, IA, monitoramento, atualizações e modo leve. |

### Recursos

- **Idiomas:** português, English, Español e 中文.
- **Proteção antes de mudar:** cria um ponto de restauração e um backup .reg antes de cada mudança, e guarda tudo num registro de mudanças.
- **Janela que não trava:** as leituras do Windows rodam em segundo plano. Para PCs mais fracos há o modo leve.
- **Relatório de erros opcional:** você escolhe o que vai junto, e o arquivo sai sem o nome de usuário, sem o nome do PC e sem e-mails.
- **Botão "?" em cada item:** monta um resumo para perguntar ao Claude.

## Autenticidade

Cada versão publicada leva um `manifesto.json` com o SHA-256 de cada arquivo. O manifesto é **assinado digitalmente** (RSA 3072 + SHA-256) com uma chave que só o autor tem.

O Janus confere a assinatura e os próprios arquivos e mostra o resultado na Visão geral:

| Selo | Significado |
|---|---|
| 🟢 **Original e verificado** | A assinatura é válida e os arquivos estão intactos. |
| 🟡 **Versão nova disponível** | A atualização é baixada do GitHub e conferida antes de ser instalada. |
| 🔴 **Arquivos diferentes do original** | A cópia foi modificada. Reinstale pelo GitHub oficial. |

**Código de autenticidade:** `JN-37AD-928C`. Ele aparece em Sobre e precisa ser igual ao publicado aqui.

### Quer conferir você mesmo?

O código está todo aqui. Você pode:

- **Conferir o instalador:** extraia com `Janus-Setup-x.exe /C /T:pasta` e compare os arquivos com o repositório.
- **Montar seu próprio instalador:** `powershell -ExecutionPolicy Bypass -File instalador\montar-instalador.ps1`
- **Rodar sem instalar:** `powershell -ExecutionPolicy Bypass -STA -File Janus.ps1`

## Instalar

1. Baixe `Janus-Setup-<versão>.exe` em **Releases**.
2. O Windows pode avisar que "protegeu o computador". Isso acontece porque o instalador não tem uma assinatura comercial paga. Clique em **Mais informações → Executar assim mesmo**.
3. Confirme o pedido de administrador.

**Para desinstalar:** Configurações → Aplicativos → Janus. Os ajustes ativos continuam no Windows. Para voltar ao padrão antes, use **Ativos → Desfazer todos**.

## Créditos

- **Ideia e pedido:** [iAlencari](https://github.com/iAlencari)
- **Criado com:** [Claude Code](https://claude.ai/code) (Anthropic): escrito com o Claude Opus 5.5 e revisado com o Claude Fable 5.2

## Licença

**GPL-3.0** (veja [LICENSE](LICENSE)). Você pode estudar, modificar e redistribuir o Janus, desde que a sua versão também seja GPL-3.0 e tenha o código aberto.

**Nome e ícone:** "Janus" e o ícone do Janus identificam o projeto original. Conforme a seção 7(e) da GPL-3.0, versões modificadas precisam usar outro nome e outro ícone, e não podem se apresentar como a versão oficial.

---

## English

**Janus** shows the real state of each Windows setting, explains every change in plain language, and lets you undo everything.

- **Safety:** it creates a restore point and backups first, and keeps a change log.
- **Never weakens security:** antivirus, firewall, UAC and memory integrity are only checked, never turned off.
- **Signed releases:** an authenticity badge and updates checked by digital signature.
- **Optional error reports:** anonymized before they leave your PC.

Built with Claude Code (written with Claude Opus 5.5, reviewed with Claude Fable 5.2), from an idea by iAlencari. License: GPL-3.0. The Janus name and icon are reserved for the original project.

## Español

**Janus** muestra el estado real de cada ajuste de Windows, explica cada cambio con palabras sencillas y permite deshacerlo todo.

- **Seguridad:** antes de cambiar algo crea un punto de restauración y copias de seguridad, y lleva un registro de cambios.
- **Nunca debilita la seguridad:** el antivirus, el firewall, el UAC y la integridad de memoria solo se comprueban, nunca se desactivan.
- **Versiones firmadas:** sello de autenticidad y actualizaciones verificadas con firma digital.
- **Informes de errores opcionales:** se anonimizan antes de salir de tu PC.

Creado con Claude Code (escrito con Claude Opus 5.5, revisado con Claude Fable 5.2) a partir de una idea de iAlencari. Licencia: GPL-3.0.

## 中文

**Janus** 显示每项 Windows 设置的真实状态，用简单的语言解释每一项更改，并且所有更改都可以撤销。

- **安全：** 更改前先创建还原点和备份，并保留更改记录。
- **绝不削弱安全性：** 只检查防病毒、防火墙、UAC 和内存完整性，绝不关闭它们。
- **签名发布：** 提供真实性标识，更新通过数字签名验证。
- **可选的错误报告：** 发送前会先匿名化。

由 iAlencari 构思，使用 Claude Code 创建（Claude Opus 5.5 编写，Claude Fable 5.2 审阅）。许可证：GPL-3.0。
