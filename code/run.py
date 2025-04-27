from app import create_app

# Choose storage: 'mysql' or 'file'
app = create_app(storage_type='file')

if __name__ == '__main__':
    app.run(port=5000)