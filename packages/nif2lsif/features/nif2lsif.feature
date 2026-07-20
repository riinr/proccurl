Feature: NIF to LSIF Conversion
  As a developer working with Nim code intelligence
  I want to convert NIF AST files to LSIF graphs
  So that I can use standard tooling for code navigation

  Scenario: Convert a NIF file to LSIF graph
    Given the NIF file "packages/webdrivermcp/src/webdrivermcp.nif"
    When I convert it to LSIF
    Then the output should be valid JSON lines
    And the output should contain a metaData vertex
    And the output should contain a project vertex
    And the output should contain a document vertex

  Scenario: Convert a NIF deps file to LSIF graph
    Given the NIF file "packages/webdrivermcp/src/webdrivermcp.deps.nif"
    When I convert it to LSIF
    Then the output should be valid JSON lines
    And the output should contain a metaData vertex
    And the output should contain a project vertex
    And the output should contain a document vertex

  Scenario: LSIF output has correct document URI
    Given the NIF file "packages/webdrivermcp/src/webdrivermcp.nif"
    When I convert it to LSIF
    Then the document vertex URI should contain webdrivermcp.nif

  Scenario: LSIF output contains project-document containment
    Given the NIF file "packages/webdrivermcp/src/webdrivermcp.nif"
    When I convert it to LSIF
    Then the output should contain contains edges
