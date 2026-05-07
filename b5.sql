-- 1. Procedure phụ: Tìm giường trống
DELIMITER //
CREATE PROCEDURE find_available_bed(
    IN p_dept_id INT,
    OUT p_bed_id INT
)
BEGIN
    -- Tìm giường đầu tiên có trạng thái trống tại khoa chỉ định
    SET p_bed_id = NULL; -- Mặc định là không tìm thấy
    SELECT bed_id INTO p_bed_id
    FROM beds
    WHERE dept_id = p_dept_id AND status = 'Available'
    LIMIT 1;
END //

-- 2. Procedure Master: Điều phối chính
CREATE PROCEDURE transfer_patient_one_touch(
    IN p_patient_id INT,
    IN p_target_dept_id INT,
    OUT p_new_bed_id INT,
    OUT p_message VARCHAR(255)
)
BEGIN
    -- Khai báo biến cục bộ
    DECLARE v_current_status VARCHAR(20);
    DECLARE v_old_bed_id INT;
    DECLARE v_dept_name VARCHAR(100);
    DECLARE v_found_bed_id INT;
    -- Bước 1: Lấy thông tin hiện tại của bệnh nhân
    SELECT status, current_bed_id INTO v_current_status, v_old_bed_id
    FROM patients 
    WHERE patient_id = p_patient_id;
    -- Bước 2: Kiểm tra các "Bẫy" logic bằng IF...ELSE
    -- Kiểm tra trạng thái bệnh nhân
    IF v_current_status = 'Completed' THEN
        SET p_message = 'Lỗi: Bệnh nhân đã xuất viện, không thể chuyển khoa.';
        SET p_new_bed_id = NULL;
    -- Kiểm tra xem khoa đích có tồn tại không
    ELSEIF NOT EXISTS (SELECT 1 FROM departments WHERE dept_id = p_target_dept_id) THEN
        SET p_message = 'Mã khoa đích không tồn tại trên hệ thống.';
        SET p_new_bed_id = NULL;
    ELSE
        -- Bước 3: Tìm giường tại khoa mới
        CALL find_available_bed(p_target_dept_id, v_found_bed_id);
        -- Kiểm tra nếu hết giường
        IF v_found_bed_id IS NULL THEN
            SELECT dept_name INTO v_dept_name FROM departments WHERE dept_id = p_target_dept_id;
            SET p_message = CONCAT('Từ chối: Khoa ', v_dept_name, ' hiện đã hết giường trống.');
            SET p_new_bed_id = NULL;
        ELSE
            -- Bước 4: Thực hiện chuyển giường (Dữ liệu bắt đầu thay đổi từ đây)
            -- A. Giải phóng giường cũ (Nếu có)
            IF v_old_bed_id IS NOT NULL THEN
                UPDATE beds SET status = 'Available' WHERE bed_id = v_old_bed_id;
            END IF;
            -- B. Đánh dấu giường mới là đã có người (Occupied)
            UPDATE beds SET status = 'Occupied' WHERE bed_id = v_found_bed_id;
            -- C. Cập nhật ID giường mới vào hồ sơ bệnh nhân
            UPDATE patients SET current_bed_id = v_found_bed_id WHERE patient_id = p_patient_id;
            -- Trả về kết quả thành công
            SET p_new_bed_id = v_found_bed_id;
            SET p_message = CONCAT('Đã chuyển bệnh nhân đến giường ', v_found_bed_id);
        END IF;
    END IF;
END //
DELIMITER ;

-- Kịch bản kiểm thử (Test Cases)

-- Chuẩn bị biến hứng kết quả
SET @out_bed = 0;
SET @out_msg = '';

-- Kịch bản 1: Chuyển khoa thành công
CALL transfer_patient_one_touch(101, 5, @out_bed, @out_msg);
SELECT @out_bed, @out_msg;

-- Kịch bản 2: Bẫy hết giường trống (Giả sử Khoa 9 đã đầy)
CALL transfer_patient_one_touch(102, 9, @out_bed, @out_msg);
SELECT @out_bed, @out_msg;

-- Kịch bản 3: Bẫy bệnh nhân đã xuất viện (Status = 'Completed')
CALL transfer_patient_one_touch(103, 2, @out_bed, @out_msg);
SELECT @out_bed, @out_msg;

-- Kịch bản 4: Chuyển vào một Khoa không tồn tại (Dept_ID = 999)
CALL transfer_patient_one_touch(101, 999, @out_bed, @out_msg);
SELECT @out_bed, @out_msg;
