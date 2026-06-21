# Railslift

Railslift is a Ruby CLI for planning and executing Rails upgrades.

## Goals

- Detect Rails projects
- Generate upgrade plans
- Analyze upgrade risks
- Assist with Rails upgrades using AI

## Architecture

lib/
  railslift/
    cli.rb
    project_detector.rb
    upgrade_planner.rb

## Commands

railslift doctor
railslift plan --target VERSION

## Principles

- Deterministic first
- AI second
- Never modify files without user approval
- Prefer official Rails upgrade paths