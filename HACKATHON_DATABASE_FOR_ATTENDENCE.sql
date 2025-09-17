-- 1. Create Database

IF DB_ID('Attendance_Checking') IS NOT NULL
    DROP DATABASE Attendance_Checking;
GO

CREATE DATABASE Attendance_Checking;
GO
USE Attendance_Checking;
GO


-- 2. Classes Table

CREATE TABLE Classes (
    class_id VARCHAR(10) PRIMARY KEY,
    course_name VARCHAR(50),
    faculty_id VARCHAR(10)
);
GO


-- 3. Students Table

CREATE TABLE Students (
    student_id VARCHAR(10) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE,
    class_id VARCHAR(10),
    student_attendance INT DEFAULT 0, -- tracks total valid attendance
    photo VARBINARY(MAX) NULL,
    FOREIGN KEY (class_id) REFERENCES Classes(class_id)
);
GO


-- 4. Sessions Table

CREATE TABLE Sessions (
    session_id INT IDENTITY(1,1) PRIMARY KEY,
    class_id VARCHAR(10),
    session_date DATETIME,
    qr_code VARCHAR(255) UNIQUE,
    attendance_count INT DEFAULT 0,
    FOREIGN KEY (class_id) REFERENCES Classes(class_id)
);
GO

-- 5. Attendance Table

CREATE TABLE Attendance (
    attendance_id INT IDENTITY(1,1) PRIMARY KEY,
    student_id VARCHAR(10),
    session_id INT,
    scan_time DATETIME,
    status VARCHAR(20) DEFAULT 'Present',
    FOREIGN KEY (student_id) REFERENCES Students(student_id),
    FOREIGN KEY (session_id) REFERENCES Sessions(session_id)
);
GO


-- 6. Analytics Table

CREATE TABLE Analytics (
    analytics_id INT IDENTITY(1,1) PRIMARY KEY,
    class_id VARCHAR(10),
    session_id INT,
    report_date DATE,
    total_attendees INT,
    absentee_count INT,
    FOREIGN KEY (class_id) REFERENCES Classes(class_id),
    FOREIGN KEY (session_id) REFERENCES Sessions(session_id)
);
GO


-- 7. Procedure: MarkAttendance

IF OBJECT_ID('dbo.MarkAttendance', 'P') IS NOT NULL
    DROP PROCEDURE dbo.MarkAttendance;
GO

CREATE PROCEDURE dbo.MarkAttendance
    @p_student_id VARCHAR(10),
    @p_qr_code    VARCHAR(255),
    @p_scan_time  DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @v_session_id INT;
    DECLARE @v_class_id   VARCHAR(10);
    DECLARE @v_count      INT;

    BEGIN TRANSACTION;
    BEGIN TRY
        -- Find session by QR code (valid for 15 minutes)
        SELECT TOP (1)
            @v_session_id = session_id,
            @v_class_id   = class_id
        FROM Sessions
        WHERE qr_code = @p_qr_code
          AND @p_scan_time BETWEEN session_date AND DATEADD(MINUTE, 15, session_date);

        IF @v_session_id IS NOT NULL
        BEGIN
            -- Check if student enrolled
            SELECT @v_count = COUNT(*)
            FROM Students
            WHERE student_id = @p_student_id
              AND class_id   = @v_class_id;

            IF @v_count > 0
            BEGIN
                -- Duplicate scan check
                SELECT @v_count = COUNT(*)
                FROM Attendance
                WHERE student_id = @p_student_id
                  AND session_id = @v_session_id;

                IF @v_count = 0
                BEGIN
                    INSERT INTO Attendance (student_id, session_id, scan_time, status)
                    VALUES (@p_student_id, @v_session_id, @p_scan_time, 'Present');

                    UPDATE Sessions
                    SET attendance_count = attendance_count + 1
                    WHERE session_id = @v_session_id;

                    UPDATE Students
                    SET student_attendance = student_attendance + 1
                    WHERE student_id = @p_student_id;

                    COMMIT TRANSACTION;
                    PRINT 'Attendance marked successfully';
                END
                ELSE
                BEGIN
                    ROLLBACK TRANSACTION;
                    PRINT 'Duplicate scan detected';
                END
            END
            ELSE
            BEGIN
                ROLLBACK TRANSACTION;
                PRINT 'Student not enrolled in class';
            END
        END
        ELSE
        BEGIN
            ROLLBACK TRANSACTION;
            PRINT 'Invalid or expired QR code';
        END
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrNum INT = ERROR_NUMBER();
        RAISERROR('MarkAttendance failed (Err %d): %s', 16, 1, @ErrNum, @ErrMsg);
    END CATCH
END;
GO


-- 8. Procedure: GenerateAnalytics

IF OBJECT_ID('dbo.GenerateAnalytics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.GenerateAnalytics;
GO

CREATE PROCEDURE dbo.GenerateAnalytics
    @p_class_id   VARCHAR(10),
    @p_session_id INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @v_total     INT;
    DECLARE @v_attendees INT;

    SELECT @v_total = COUNT(*) 
    FROM Students 
    WHERE class_id = @p_class_id;

    SELECT @v_attendees = COUNT(*) 
    FROM Attendance 
    WHERE session_id = @p_session_id
      AND status = 'Present';

    INSERT INTO Analytics (class_id, session_id, report_date, total_attendees, absentee_count)
    VALUES (@p_class_id, @p_session_id, CAST(GETDATE() AS DATE), @v_attendees, @v_total - @v_attendees);

    PRINT 'Analytics generated';
END;
GO


-- 9. Procedure: CleanAttendanceData

IF OBJECT_ID('dbo.CleanAttendanceData', 'P') IS NOT NULL
    DROP PROCEDURE dbo.CleanAttendanceData;
GO

CREATE PROCEDURE dbo.CleanAttendanceData
AS
BEGIN
    SET NOCOUNT ON;

    -- Remove duplicate scans (keep earliest)
    ;WITH Ranked AS (
        SELECT attendance_id,
               ROW_NUMBER() OVER (PARTITION BY student_id, session_id ORDER BY scan_time ASC) AS rn
        FROM Attendance
    )
    DELETE FROM Attendance
    WHERE attendance_id IN (SELECT attendance_id FROM Ranked WHERE rn > 1);

    -- Mark invalid scans (after 15 min of session start)
    UPDATE a
    SET a.status = 'Invalid'
    FROM Attendance a
    JOIN Sessions s ON a.session_id = s.session_id
    WHERE a.scan_time > DATEADD(MINUTE, 15, s.session_date);

    PRINT 'Attendance data cleaned';
END;
GO


-- 10. Sample Data

-- Classes
INSERT INTO Classes (class_id, course_name, faculty_id)
VALUES ('C101', 'Database Systems', 'F001');

-- Students
INSERT INTO Students (student_id, name, email, class_id)
VALUES 
('S101', 'Harshit',  'harshit@example.com', 'C101'),
('S102', 'Somnath',  'somnath@example.com', 'C101'),
('S103', 'Hemang',   'hemang@example.com', 'C101'),
('S104', 'Adil',     'adil@example.com',   'C101');

-- Session
INSERT INTO Sessions (class_id, session_date, qr_code)
VALUES ('C101', '2025-09-17 10:00:00', 'QR123');


-- 11. Test Calls

-- Mark Attendance
EXEC MarkAttendance 'S101', 'QR123', '2025-09-17 10:05:00'; -- Harshit Present
EXEC MarkAttendance 'S102', 'QR123', '2025-09-17 10:07:00'; -- Somnath Present
EXEC MarkAttendance 'S103', 'QR123', '2025-09-17 10:20:00'; -- Hemang Late -> Invalid
EXEC MarkAttendance 'S104', 'QR123', '2025-09-17 10:10:00'; -- Adil Present

-- Generate Analytics
EXEC GenerateAnalytics 'C101', 1;

-- Clean Data
EXEC CleanAttendanceData;


-- 12. Check Results

SELECT * FROM Students;   -- Attendance totals per student
SELECT * FROM Sessions;   -- Attendance count per session
SELECT * FROM Attendance; -- All scans
SELECT * FROM Analytics;  -- Analytics summary
GO


