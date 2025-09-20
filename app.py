from flask import Flask, render_template, request, redirect, url_for
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///blog.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

# データベースモデル
class Post(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    content = db.Column(db.Text, nullable=False)
    author = db.Column(db.String(50), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    tags = db.Column(db.String(200))
    status = db.Column(db.String(20), default='draft')  # draft / published

    def __repr__(self):
        return f"<Post {self.title}>"

# DB作成
with app.app_context():
    db.create_all()

# トップページ（公開記事一覧）
@app.route('/')
def index():
    posts = Post.query.filter_by(status='published').order_by(Post.created_at.desc()).all()
    return render_template('index.html', posts=posts)

# 新規投稿
@app.route('/create', methods=['GET', 'POST'])
def create():
    if request.method == 'POST':
        title = request.form['title']
        content = request.form['content']
        author = request.form['author']
        tags = request.form['tags']
        status = request.form['status']
        post = Post(title=title, content=content, author=author, tags=tags, status=status)
        db.session.add(post)
        db.session.commit()
        return redirect(url_for('index'))
    return render_template('create.html')

# 投稿編集
@app.route('/edit/<int:id>', methods=['GET', 'POST'])
def edit(id):
    post = Post.query.get_or_404(id)
    if request.method == 'POST':
        post.title = request.form['title']
        post.content = request.form['content']
        post.author = request.form['author']
        post.tags = request.form['tags']
        post.status = request.form['status']
        db.session.commit()
        return redirect(url_for('index'))
    return render_template('edit.html', post=post)

# 投稿削除
@app.route('/delete/<int:id>')
def delete(id):
    post = Post.query.get_or_404(id)
    db.session.delete(post)
    db.session.commit()
    return redirect(url_for('index'))

if __name__ == '__main__':
    app.run(debug=True)
