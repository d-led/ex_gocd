# GoCD Testing Strategy Analysis

## Overview

GoCD employs a comprehensive, multi-layered testing strategy covering unit, integration, and functional tests. The codebase contains **1173+ test files** demonstrating mature testing practices.

## Test Structure & Organization

### Directory Organization

```shell
gocd/
├── base/src/test/java/              # Core utility tests
├── server/src/
│   ├── test/                        # Unit tests (fast)
│   ├── test-integration/            # Integration tests
│   └── testFixtures/                # Shared test utilities
└── [module]/src/test/               # Module-specific tests
```

**Key Pattern**: Clear separation between fast unit tests and slower integration tests

### Test Categories

#### 1. **Unit Tests** (`src/test/`)

- **139+ service tests** alone
- Fast, isolated tests using mocks
- Test individual components in isolation
- Example: `StageServiceTest`, `SecurityServiceTest`

#### 2. **Integration Tests** (`src/test-integration/`)

- Test component interactions
- Use Spring context and real dependencies
- Database integration tests
- Example: `GoDashboardCurrentStateLoaderIntegrationTest`

## Testing Frameworks & Tools

### Java Backend

```java
// Core Testing Stack
@ExtendWith(MockitoExtension.class)  // JUnit 5 with Mockito
@ExtendWith(SpringExtension.class)   // Spring integration tests

// Assertion Library
import static org.assertj.core.api.Assertions.assertThat;  // AssertJ (fluent)

// Mocking
@Mock
private StageDao stageDao;
@Mock
private SecurityService securityService;

// Test Infrastructure
@TempDir File folder;  // JUnit 5 temp directories
```

### Key Libraries

1. **JUnit 5** (Jupiter) - Modern test framework
   - `@Test`, `@BeforeEach`, `@AfterEach`
   - `@Nested` for grouped tests
   - `@ExtendWith` for extensions

2. **Mockito** - Mocking framework
   - `@Mock` for dependencies
   - `when().thenReturn()` for stubbing
   - `verify()` for behavior verification

3. **AssertJ** - Fluent assertions
   - `assertThat(value).isEqualTo(expected)`
   - Readable, IDE-friendly
   - Better error messages than JUnit assertions

4. **Spring Test** - Integration testing
   - `@ContextConfiguration` for Spring context
   - Real beans and database interactions

## Testing Patterns & Best Practices

### 1. **Clear Test Structure**

```java
public class StageServiceTest {
    // Dependencies (mocks)
    private StageDao stageDao;
    private SecurityService securityService;

    @BeforeEach
    public void setUp() {
        // Initialize mocks and test fixtures
        stageDao = mock(StageDao.class);
        securityService = alwaysAllow();
    }

    @Test
    public void shouldFindStageSummaryModelForGivenStageIdentifier() {
        // Arrange - setup test data
        Stage stage = StageMother.completedStageInstanceWithTwoPlans("stage_name");
        when(stageDao.getAllRunsOfStage(...)).thenReturn(stages);

        // Act - execute the behavior
        StageSummaryModel result = service.findStageSummaryByIdentifier(...);

        // Assert - verify outcomes
        assertThat(result.getName()).isEqualTo(stage.getName());
        assertThat(result.getState()).isEqualTo(stage.stageState());
    }
}
```

### 2. **Test Mothers Pattern**

GoCD extensively uses **Test Data Builders** (Mother pattern):

```java
// Centralized test data creation
Stage stage = StageMother.completedStageInstanceWithTwoPlans("stage_name");
PipelineConfig config = PipelineConfigMother.createPipelineConfigWithStages("a-pipeline", "a-stage");
Job job = JobInstanceMother.completed("job-name");
```

**Benefits**:

- Consistent test data across tests
- Reduces duplication
- Makes tests more readable
- Easy to update when models change

### 3. **Descriptive Test Names**

```java
// Pattern: should[ExpectedBehavior]When[Condition]
shouldReturnEmptyWhenNoPipelinesArePresentInConfig()
shouldShowMultiplePipelineInstancesFromSamePipelineWhenMultipleAreRunning()
shouldPopulateNewCacheWithProjectsFromOldCacheWhenTheyExist()
```

### 4. **Nested Test Organization**

```java
@ExtendWith(MockitoExtension.class)
public class StageServiceTest {

    @Nested
    class WhenFindingStages {
        @Test
        void shouldFindByIdentifier() { }

        @Test
        void shouldThrowWhenNotFound() { }
    }

    @Nested
    class WhenCancelling {
        @Test
        void shouldCancelRunningStage() { }
    }
}
```

### 5. **Integration Test Patterns**

```java
@ExtendWith(SpringExtension.class)
@ContextConfiguration(locations = {
    "classpath:/applicationContext-global.xml",
    "classpath:/applicationContext-dataLocalAccess.xml",
    "classpath:/testPropertyConfigurer.xml"
})
public class GoDashboardCurrentStateLoaderIntegrationTest {

    @Autowired
    private GoDashboardCurrentStateLoader loader;

    @Autowired
    private DatabaseAccessHelper dbHelper;

    @BeforeEach
    public void setUp(@TempDir File configDir) {
        dbHelper.onSetUp();
        configHelper.usingCruiseConfigDao(goConfigDao);
    }

    @AfterEach
    public void tearDown() {
        dbHelper.onTearDown();
    }

    @Test
    public void shouldReturnSingleDashboardForSingleCompletedGreenPipelineInstance() {
        // Given real database setup
        PipelineConfig config = configHelper.addPipeline(...);
        Pipeline pipeline = dbHelper.newPipelineWithAllStagesPassed(config);

        // When
        List<GoDashboardPipeline> result = loader.allPipelines(...);

        // Then
        assertThat(result).hasSize(1);
        assertThat(result.getFirst().model().getLatestPipelineInstance().getId())
            .isEqualTo(pipeline.getId());
    }
}
```

## Dashboard-Specific Test Examples

### Dashboard Integration Test

```java
// Tests real dashboard loading with database
public class GoDashboardCurrentStateLoaderIntegrationTest {

    @Test
    public void shouldReturnEmptyWhenNoPipelinesArePresentInConfig() {
        goConfigService.forceNotifyListeners();
        assertThat(goConfigService.getAllPipelineConfigs()).isEmpty();

        List<GoDashboardPipeline> result = loader.allPipelines(...);

        assertThat(result).isEmpty();
    }

    @Test
    public void shouldShowMultiplePipelineInstancesWhenMultipleAreRunning() {
        // Setup: 2 pipeline instances running different stages
        Pipeline p1 = dbHelper.newPipelineWithFirstStagePassed(config);
        dbHelper.scheduleStage(p1, config.getStage("b-stage"));
        Pipeline p2 = dbHelper.newPipelineWithFirstStageScheduled(config);

        List<GoDashboardPipeline> result = loader.allPipelines(...);

        assertThat(result.getFirst().model().getActivePipelineInstances())
            .hasSize(2);
        assertThat(result.getFirst().model().getLatestPipelineInstance().getId())
            .isEqualTo(p2.getId());
    }
}
```

### Dashboard Unit Test

```java
public class GoDashboardPipelinesTest {
    @Test
    public void shouldSetLastUpdatedTime() {
        TimeStampBasedCounter provider = mock(TimeStampBasedCounter.class);
        when(provider.getNext()).thenReturn(100L);

        GoDashboardPipelines result = new GoDashboardPipelines(new HashMap<>(), provider);

        assertThat(result.lastUpdatedTimeStamp()).isEqualTo(100L);
    }
}
```

## Key Testing Principles from GoCD

### 1. **Test Behavior, Not Implementation**

- Focus on what the component does, not how
- Use interfaces and mocks to isolate
- Verify outcomes, not internal state

### 2. **Fast Tests First**

- Unit tests in `test/` run quickly
- Integration tests separated for slower runs
- Enables rapid feedback during development

### 3. **Comprehensive Coverage**

- Unit tests for individual components
- Integration tests for component interactions
- End-to-end tests for full workflows

### 4. **Readable Tests**

- Descriptive test names explain intent
- Clear arrange-act-assert structure
- Test mothers reduce boilerplate

### 5. **Isolated Tests**

- Each test independent (can run in any order)
- Setup/teardown in `@BeforeEach`/`@AfterEach`
- No shared mutable state between tests

### 6. **Meaningful Assertions**

```java
// Bad - unclear what's being tested
assertThat(stage.getResult()).isEqualTo(StageResult.Unknown);

// Good - intention clear from test name + assertion
@Test
public void shouldHaveUnknownResultWhenStageIsBuilding() {
    assertThat(buildingStage.getResult()).isEqualTo(StageResult.Unknown);
}
```

## Test Organization Best Practices

### File Naming

- Test class: `[ComponentName]Test.java`
- Integration test: `[ComponentName]IntegrationTest.java`
- Co-located with source: same package structure

### Test Grouping

```java
// Group related tests with @Nested
class StageServiceTest {
    @Nested
    class FindOperations {
        @Test void shouldFindById() { }
        @Test void shouldFindByIdentifier() { }
    }

    @Nested
    class CancelOperations {
        @Test void shouldCancelStage() { }
        @Test void shouldNotCancelCompletedStage() { }
    }
}
```

### Fixture Management

```java
// Shared setup for related tests
@BeforeEach
public void setUp() {
    // Common initialization
    securityService = alwaysAllow();
    stageDao = mock(StageDao.class);
}

// Specific setup in test method
@Test
public void specificTest() {
    // Additional test-specific setup
    when(stageDao.findStageWithIdentifier(...)).thenReturn(stage);
}
```

## Recommendations for ex_gocd Phoenix Tests

Based on GoCD's testing strategy, we should adopt:

1. **ExUnit with clear structure** (equivalent to JUnit 5)
2. **Mox for mocking** (equivalent to Mockito)
3. **Phoenix.LiveViewTest** for LiveView testing
4. **Test helpers/factories** (equivalent to Mother pattern)
5. **Separation**: unit vs integration tests
6. **Descriptive test names**: `test "renders dashboard when pipeline is running"`
7. **Arrange-Act-Assert** pattern in all tests
8. **Fast feedback**: run unit tests frequently

### Test Coverage Areas

1. **LiveView Tests**
   - Mount and render
   - Event handling (search, dropdown)
   - State updates
   - DOM assertions

2. **Component Tests**
   - Layout rendering
   - Navigation active states
   - Accessibility attributes

3. **Integration Tests**
   - Database queries (when added)
   - Real data flow
   - Complete user workflows

4. **Unit Tests**
   - Helper functions
   - Business logic
   - Data transformations
