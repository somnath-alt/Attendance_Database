--  Create Database
CREATE DATABASE IF NOT EXISTS attendence_checking;
USE attendence_checking;

-- Classes Table
CREATE TABLE Classes (
    class_id VARCHAR(10) PRIMARY KEY,
    course_name VARCHAR(50),
    faculty_id VARCHAR(10),
    INDEX idx_class_id (class_id)
);

--  Students Table (added student_attendance column)
CREATE TABLE Students (
    student_id VARCHAR(10) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE,
    class_id VARCHAR(10),
    student_attendance INT DEFAULT 0, -- tracks total valid attendance
    photo BLOB,
    FOREIGN KEY (class_id) REFERENCES Classes(class_id),
    INDEX idx_student_id (student_id)
);

-- Sessions Table
CREATE TABLE Sessions (
    session_id INT AUTO_INCREMENT PRIMARY KEY,
    class_id VARCHAR(10),
    session_date DATETIME,
    qr_code VARCHAR(255) UNIQUE,
    attendance_count INT DEFAULT 0,
    FOREIGN KEY (class_id) REFERENCES Classes(class_id),
    INDEX idx_session_date (session_date)
);

--  Attendance Table
CREATE TABLE Attendance (
    attendance_id INT AUTO_INCREMENT PRIMARY KEY,
    student_id VARCHAR(10),
    session_id INT,
    scan_time DATETIME,
    status ENUM('Present', 'Invalid') DEFAULT 'Present',
    FOREIGN KEY (student_id) REFERENCES Students(student_id),
    FOREIGN KEY (session_id) REFERENCES Sessions(session_id),
    INDEX idx_scan_time (scan_time)
);

--  Analytics Table
CREATE TABLE Analytics (
    analytics_id INT AUTO_INCREMENT PRIMARY KEY,
    class_id VARCHAR(10),
    session_id INT,
    report_date DATE,
    total_attendees INT,
    absentee_count INT,
    FOREIGN KEY (class_id) REFERENCES Classes(class_id),
    FOREIGN KEY (session_id) REFERENCES Sessions(session_id)
);

--  Procedure to Mark Attendance (updated with student_attendance increment)
DELIMITER //
CREATE PROCEDURE MarkAttendance (
    IN p_student_id VARCHAR(10),
    IN p_qr_code VARCHAR(255),
    IN p_scan_time DATETIME
)
BEGIN
    DECLARE v_session_id INT;
    DECLARE v_class_id VARCHAR(10);
    DECLARE v_count INT;

    START TRANSACTION;

    -- Find session by QR code (valid for 15 minutes)
    SELECT session_id, class_id INTO v_session_id, v_class_id
    FROM Sessions
    WHERE qr_code = p_qr_code
      AND p_scan_time BETWEEN session_date AND session_date + INTERVAL 15 MINUTE;

    IF v_session_id IS NOT NULL THEN
        -- Check if student is enrolled in the class
        SELECT COUNT(*) INTO v_count
        FROM Students
        WHERE student_id = p_student_id AND class_id = v_class_id;

        IF v_count > 0 THEN
            -- Check for duplicate scan
            SELECT COUNT(*) INTO v_count
            FROM Attendance
            WHERE student_id = p_student_id AND session_id = v_session_id;

            IF v_count = 0 THEN
                -- Insert attendance record
                INSERT INTO Attendance (student_id, session_id, scan_time, status)
                VALUES (p_student_id, v_session_id, p_scan_time, 'Present');

                -- Increment session attendance count
                UPDATE Sessions
                SET attendance_count = attendance_count + 1
                WHERE session_id = v_session_id;

                -- Increment student's total attendance
                UPDATE Students
                SET student_attendance = student_attendance + 1
                WHERE student_id = p_student_id;

                COMMIT;
                SELECT 'Attendance marked successfully' AS message;
            ELSE
                ROLLBACK;
                SELECT 'Duplicate scan detected' AS message;
            END IF;
        ELSE
            ROLLBACK;
            SELECT 'Student not enrolled in class' AS message;
        END IF;
    ELSE
        ROLLBACK;
        SELECT 'Invalid or expired QR code' AS message;
    END IF;
END //
DELIMITER ;

--  Procedure to Generate Analytics
DELIMITER //
CREATE PROCEDURE GenerateAnalytics (
    IN p_class_id VARCHAR(10),
    IN p_session_id INT
)
BEGIN
    DECLARE v_total INT;
    DECLARE v_absentees INT;

    SELECT COUNT(*) INTO v_total FROM Students WHERE class_id = p_class_id;
    SELECT COUNT(*) INTO v_absentees FROM Attendance WHERE session_id = p_session_id AND status = 'Present';

    INSERT INTO Analytics (class_id, session_id, report_date, total_attendees, absentee_count)
    VALUES (p_class_id, p_session_id, CURDATE(), v_absentees, v_total - v_absentees);

    SELECT 'Analytics generated' AS message;
END //
DELIMITER ;

--  Data Cleaning Procedure
DELIMITER //
CREATE PROCEDURE CleanAttendanceData()
BEGIN
    -- Remove duplicate scans (keep earliest)
    DELETE a1
    FROM Attendance a1
    JOIN Attendance a2
      ON a1.student_id = a2.student_id
     AND a1.session_id = a2.session_id
     AND a1.scan_time > a2.scan_time;

    -- Mark invalid scans (after 15 min of session start)
    UPDATE Attendance a
    JOIN Sessions s ON a.session_id = s.session_id
    SET a.status = 'Invalid'
    WHERE a.scan_time > s.session_date + INTERVAL 15 MINUTE;
END //
DELIMITER ;


  
-- Checking the Attendance status for all students in a particular session

SELECT s.student_id, s.name, c.course_name, se.session_date,
       COALESCE(a.status, 'Absent') AS status
FROM Students s
JOIN Classes c ON s.class_id = c.class_id
JOIN Sessions se ON se.class_id = c.class_id
LEFT JOIN Attendance a 
       ON s.student_id = a.student_id 
      AND se.session_id = a.session_id
WHERE se.session_id = 1;
  


-- Check Process
SELECT student_id, name, student_attendance
FROM Students;

INSERT INTO Classes (class_id, course_name, faculty_id)
VALUES ('C101', 'Math', 'F001');

INSERT INTO Students (student_id, name, email, class_id)
VALUES 
('S101', 'Harshit', 'harshit@example.com', 'C101'),
('S102', 'Somnath', 'somnath@example.com', 'C101'),
('S103', 'Hemang',  'hemang@example.com',  'C101'),
('S104', 'Adil',    'adil@example.com',    'C101');

SELECT * FROM students;
INSERT INTO Sessions (class_id, session_date, qr_code)
VALUES ('C101', '2025-09-16 10:00:00', 'QR123');

SELECT * FROM Sessions;

CALL MarkAttendance('S103', 'QR123', '2025-09-16 10:05:00'); -- Hemang
CALL MarkAttendance('S102', 'QR123', '2025-09-16 10:07:00'); -- Somnath

SELECT * FROM Attendance;
select* FROM Students;

CALL GenerateAnalytics('C101', 1);

SELECT * FROM Analytics;

