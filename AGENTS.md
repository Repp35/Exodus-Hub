# Regras de manutenção do Exodus Hub

## Testes essenciais

Mantenha somente verificações essenciais de permissões, APIs internas, contratos,
exports, dependências, sintaxe/compilação Luau e análise básica de globais.
Verificações de integridade dos catálogos e arquivos gerados também são permitidas.

Não crie nem mantenha suítes extras de comportamento, layout, animações,
funcionalidades, downloads, loader, informações ou auto execute sem pedido
explícito do usuário. Corrigir uma funcionalidade não autoriza adicionar esses testes.

## Documentação e entrega

Crie ou altere documentação somente quando o usuário pedir explicitamente.
Este arquivo registra a política solicitada pelo usuário.

Faça as alterações diretamente na main, em um único commit por solicitação.
Não crie branches ou pull requests sem pedido explícito.
