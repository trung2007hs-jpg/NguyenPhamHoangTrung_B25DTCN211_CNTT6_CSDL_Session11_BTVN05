-- 1. Procedure phụ: Tìm giường trống
DELIMITER //
CREATE PROCEDURE find_available_bed(
    IN p_dept_id INT,
    OUT p_bed_id INT
)
BEGIN
    -- Tìm giường đầu tiên có trạng thái 'Available' tại khoa chỉ định
    -- Sử dụng FOR UPDATE để khóa hàng, tránh y tá khác chiếm mất trong cùng 1 giây
    SELECT bed_id INTO p_bed_id
    FROM beds
    WHERE dept_id = p_dept_id AND status = 'Available'
    LIMIT 1
    FOR UPDATE;
END //

-- 2. Procedure Master: Điều phối chính
CREATE PROCEDURE transfer_patient_one_touch(
    IN p_patient_id INT,
    IN p_target_dept_id INT,
    OUT p_new_bed_id INT,
    OUT p_message VARCHAR(255)
)
/* - START TRANSACTION: Mở một "bản nháp" an toàn. Dữ liệu chưa thay đổi thật.
   - ROLLBACK: Lệnh "Hoàn tác". Nếu gặp lỗi (hết giường, sai mã), 
               hệ thống xóa nháp, trả dữ liệu về y như cũ.
   - COMMIT: Lệnh "Chốt đơn". Khi mọi bước đều OK, dữ liệu mới được lưu thật.
*/
BEGIN
    DECLARE v_current_status VARCHAR(20);
    DECLARE v_old_bed_id INT;
    DECLARE v_dept_name VARCHAR(100);
    DECLARE v_found_bed_id INT;
    -- Bắt đầu giao dịch để đảm bảo an toàn dữ liệu
    START TRANSACTION;
    -- Bẫy dữ liệu 1: Kiểm tra bệnh nhân và trạng thái hồ sơ
    SELECT status, current_bed_id INTO v_current_status, v_old_bed_id
    FROM patients WHERE patient_id = p_patient_id;
    IF v_current_status = 'Completed' THEN
        SET p_message = 'Error: Patient already discharged.';
        ROLLBACK;
    -- Bẫy dữ liệu 2: Kiểm tra khoa đích tồn tại
    ELSEIF NOT EXISTS (SELECT 1 FROM departments WHERE dept_id = p_target_dept_id) THEN
        SET p_message = 'Error: Department ID does not exist.';
        ROLLBACK;
    ELSE
        -- Gọi Procedure phụ để dò giường
        CALL find_available_bed(p_target_dept_id, v_found_bed_id);

        -- Bẫy Overbooking: Hết giường
        IF v_found_bed_id IS NULL THEN
            SELECT dept_name INTO v_dept_name FROM departments WHERE dept_id = p_target_dept_id;
            SET p_message = CONCAT('Rejected: Department ', v_dept_name, ' is full.');
            ROLLBACK;
        ELSE
            -- Thực thi chuyển giường "1 chạm"
            -- Bước A: Giải phóng giường cũ
            UPDATE beds SET status = 'Available' WHERE bed_id = v_old_bed_id;
            -- Bước B: Gán và Khóa giường mới
            UPDATE beds SET status = 'Occupied' WHERE bed_id = v_found_bed_id;
            -- Bước C: Cập nhật hồ sơ bệnh nhân
            UPDATE patients SET current_bed_id = v_found_bed_id WHERE patient_id = p_patient_id;
            SET p_new_bed_id = v_found_bed_id;
            SET p_message = 'Success: Patient transferred successfully.';
            COMMIT;
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