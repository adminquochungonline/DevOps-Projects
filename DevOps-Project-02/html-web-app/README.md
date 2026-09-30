# DevOps Project 02 Web Application

Static website dùng chung cho cả hai phiên bản triển khai AWS và Azure của Project 02.

## Nội dung

- `index.html`, `header.html`, `ok.htm`, `error.htm`: các trang HTML hiện có.
- `css/`, `js/`, `images/`: asset của website.
- `WEB-INF/web.xml`: artifact servlet cũ; project hiện không chứa servlet implementation hoặc Java runtime tương ứng.

## Deployment entrypoints

- AWS: `../VPC Architecture/script.sh` và hướng dẫn trong `../VPC Architecture/README.md`.
- Azure: `../Azure Architecture/bootstrap.sh` và hướng dẫn trong `../Azure Architecture/README.md`.

Azure bootstrap clone repository và copy toàn bộ thư mục này vào `/var/www/html`, sau đó tạo `/healthz` cho Application Gateway health probe. AWS script được giữ nguyên hành vi gốc để phục vụ triển khai và so sánh.

Website hiện có các link tới trang phụ và `contact.php` không tồn tại trong repository. Chúng được giữ nguyên vì nằm ngoài phạm vi chuyển đổi hạ tầng cloud.
